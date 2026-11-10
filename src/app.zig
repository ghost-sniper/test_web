const std = @import("std");
const httpz = @import("httpz");
const mock = @import("mock.zig");
const rate = @import("rate_limit.zig");

pub const App = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    config_path: []const u8,
    admin_token: []const u8,
    snapshot: mock.Snapshot,
    rate_limiter: rate.RateLimiter = .{},
    mutex: std.Io.Mutex = .init,
    reload_mutex: std.Io.Mutex = .init,
    generation: u64 = 1,

    /// Every response is materialized in res.arena before releasing the snapshot
    /// lock. Neither network writes nor configured delays retain that lock.
    pub fn handle(self: *App, req: *httpz.Request, res: *httpz.Response) void {
        const delay = self.process(req, res) catch |err| blk: {
            std.log.err("request failed: {s}", .{@errorName(err)});
            res.status = 500;
            res.content_type = .JSON;
            res.body = "{\"code\":500,\"message\":\"internal server error\"}";
            break :blk 0;
        };
        if (req.method == .HEAD) res.body = "";
        if (delay > 0) std.Io.sleep(self.io, .fromMilliseconds(delay), .awake) catch {};
    }

    fn process(self: *App, req: *httpz.Request, res: *httpz.Response) !u32 {
        // Admin endpoints deliberately do not inherit public Mock CORS policy.
        if (std.mem.eql(u8, req.url.path, "/admin") or std.mem.startsWith(u8, req.url.path, "/admin/")) {
            try self.admin(req, res);
            return 0;
        }
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        const config = self.snapshot.config;
        const allowed = try cors(config.cors, req, res);
        const is_health = std.mem.eql(u8, req.url.path, "/healthz");
        if (req.body()) |body| {
            if (body.len > 1024 * 1024) {
                try reply(res, 413, "request body exceeds 1 MiB");
                return 0;
            }
        }
        if (req.method == .OPTIONS) {
            if (!allowed) {
                try reply(res, 403, "origin not allowed");
            } else if (req.header("access-control-request-method")) |method| {
                if (!mock.validMethod(method) or !allowedHeaders(config.cors.allow_headers, req.header("access-control-request-headers") orelse "")) {
                    try reply(res, 403, "preflight method or headers not allowed");
                } else {
                    res.status = 204;
                    res.header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS");
                    res.header("Access-Control-Allow-Headers", try res.arena.dupe(u8, config.cors.allow_headers));
                    res.header("Access-Control-Max-Age", try std.fmt.allocPrint(res.arena, "{d}", .{config.cors.max_age}));
                }
            } else {
                res.status = 204;
                res.header("Allow", "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS");
            }
            return 0;
        }
        if (is_health) {
            if (req.method != .GET and req.method != .HEAD) {
                res.header("Allow", "GET, HEAD, OPTIONS");
                try reply(res, 405, "method not allowed");
            } else {
                try json(res, .{ .status = "ok", .generation = self.generation, .routes = config.routes.len });
            }
            return 0;
        }
        for (config.routes) |route| {
            if (!std.mem.eql(u8, route.method, @tagName(req.method)) or !std.mem.eql(u8, route.path, req.url.path)) continue;
            if (route.rate_limit.requests_per_second != 0 or route.rate_limit.clients.len != 0) {
                const client = clientIp(req, config.trusted_proxies);
                const limit = route.rate_limit.limitFor(client);
                const result = try self.rate_limiter.allow(self.allocator, self.io, route.method, route.path, client, limit);
                if (result != .allowed) {
                    res.header("Retry-After", "1");
                    res.header("Cache-Control", "no-store");
                    if (allowed and req.header("origin") != null) res.header("Access-Control-Expose-Headers", "Retry-After");
                    switch (result) {
                        .limited => try reply(res, 429, "too many requests"),
                        .capacity => try reply(res, 503, "rate limit tracking capacity reached"),
                        .allowed => unreachable,
                    }
                    return 0;
                }
            }
            const body = mock.parseBody(res.arena, route.request, req.body()) catch |err| {
                switch (err) {
                    error.MissingBody => try reply(res, 400, "missing request body"),
                    error.InvalidBody => try reply(res, 400, "格式不正确，请使用标准JSON格式传输"),
                    else => return err,
                }
                return 0;
            };
            var selected: ?mock.Rule = null;
            for (route.rules) |rule| {
                if (selected) |current| {
                    if (rule.priority <= current.priority) continue;
                }
                if (try matches(rule.match, body, req)) selected = rule;
            }
            if (selected) |rule| {
                const value = if (rule.response.template) mock.render(res.arena, rule.response.body, body) catch |err| {
                    if (err != error.InvalidBody) return err;
                    try reply(res, 400, "request value cannot be rendered");
                    return 0;
                } else rule.response.body;
                // Serialize while the snapshot is locked, including all strings
                // borrowed by defaults/templates from the config tree.
                if (rule.response.status != 204 and rule.response.status != 205 and rule.response.status != 304) try json(res, value);
                res.status = rule.response.status;
                for (rule.response.headers) |pair| {
                    if (std.ascii.eqlIgnoreCase(pair.name, "content-type")) res.content_type = null;
                    try res.headerOpts(pair.name, pair.value, .{ .dupe_name = true, .dupe_value = true });
                }
                return rule.response.delay_ms;
            }
            try reply(res, 404, "no matching mock rule");
            return 0;
        }
        try reply(res, 404, "mock route not found");
        return 0;
    }

    fn admin(self: *App, req: *httpz.Request, res: *httpz.Response) !void {
        res.header("Cache-Control", "no-store");
        res.header("X-Content-Type-Options", "nosniff");
        if (self.admin_token.len == 0) return reply(res, 404, "admin disabled: set MOCK_ADMIN_TOKEN and restart");
        if (try adminAsset(req, res)) return;
        const is_config = std.mem.eql(u8, req.url.path, "/admin/api/config");
        const is_reload = std.mem.eql(u8, req.url.path, "/admin/reload");
        if (!is_config and !is_reload) return reply(res, 404, "not found");
        if ((is_config and req.method != .GET and req.method != .PUT) or (is_reload and req.method != .POST)) {
            res.header("Allow", if (is_config) "GET, PUT" else "POST");
            return reply(res, 405, "method not allowed");
        }
        const auth = req.header("authorization") orelse "";
        const expected = try std.fmt.allocPrint(res.arena, "Bearer {s}", .{self.admin_token});
        if (!secureEqual(auth, expected)) {
            res.header("WWW-Authenticate", "Bearer");
            return reply(res, 401, "unauthorized");
        }
        if (is_config and req.method == .GET) return self.readConfig(res);
        if (is_config) return self.saveConfig(req, res);
        // Serialize reloads, but allow normal requests during file I/O/validation.
        try self.reload_mutex.lock(self.io);
        defer self.reload_mutex.unlock(self.io);
        var next = mock.Snapshot.load(self.io, self.allocator, self.config_path) catch |err| {
            std.log.warn("reload rejected: {s}", .{@errorName(err)});
            res.status = 400;
            return json(res, .{ .code = 400, .message = "reload rejected; previous config remains active", .reason = @errorName(err) });
        };
        self.mutex.lock(self.io) catch |err| {
            next.deinit();
            return err;
        };
        var old = self.snapshot;
        self.snapshot = next;
        self.generation += 1;
        const generation = self.generation;
        const routes = next.config.routes.len;
        self.mutex.unlock(self.io);
        old.deinit();
        try json(res, .{ .status = "reloaded", .generation = generation, .routes = routes });
    }

    fn readConfig(self: *App, res: *httpz.Response) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        res.header("ETag", try std.fmt.allocPrint(res.arena, "\"{s}\"", .{self.snapshot.revision}));
        // The validated source preserves numeric lexemes (1.0 versus 1, i64)
        // across browser edits instead of normalizing the dynamic JSON tree.
        res.body = try std.fmt.allocPrint(res.arena, "{{\"generation\":{d},\"revision\":\"{s}\",\"config\":{s}}}", .{
            self.generation, self.snapshot.revision, self.snapshot.source,
        });
        res.content_type = .JSON;
    }

    fn saveConfig(self: *App, req: *httpz.Request, res: *httpz.Response) !void {
        const if_match = req.header("if-match") orelse return reply(res, 428, "If-Match revision is required");
        const raw = req.body() orelse return reply(res, 400, "missing config body");
        if (raw.len >= 4 * 1024 * 1024) return reply(res, 413, "config must be smaller than 4 MiB");
        var next = mock.Snapshot.parse(self.allocator, raw) catch |err| {
            res.status = 400;
            return json(res, .{ .code = 400, .message = "invalid config; nothing saved", .reason = @errorName(err) });
        };
        var committed = false;
        defer if (!committed) next.deinit();
        try self.reload_mutex.lock(self.io);
        defer self.reload_mutex.unlock(self.io);
        // Only reload/save mutate the snapshot and both hold reload_mutex.
        const expected = try std.fmt.allocPrint(res.arena, "\"{s}\"", .{self.snapshot.revision});
        if (!std.mem.eql(u8, if_match, expected)) return reply(res, 409, "config changed; refresh before saving");
        const disk = std.Io.Dir.cwd().readFileAlloc(self.io, self.config_path, res.arena, .limited(4 * 1024 * 1024)) catch |err| {
            res.status = 500;
            return json(res, .{ .code = 500, .message = "cannot read config file; nothing saved", .reason = @errorName(err) });
        };
        if (!std.mem.eql(u8, &mock.digest(disk), &self.snapshot.revision)) return reply(res, 409, "config file changed externally; reload before saving");
        persist(self.io, self.config_path, raw) catch |err| {
            res.status = 500;
            return json(res, .{ .code = 500, .message = "cannot save config file; previous config remains active", .reason = @errorName(err) });
        };
        // From this commit point, cancellation must not leave disk and memory apart.
        self.mutex.lockUncancelable(self.io);
        var old = self.snapshot;
        self.snapshot = next;
        self.generation += 1;
        committed = true;
        self.mutex.unlock(self.io);
        old.deinit();
        try self.readConfig(res);
    }
};

fn clientIp(req: *httpz.Request, trusted_proxies: []const rate.ClientIp) rate.ClientIp {
    const peer = rate.ClientIp.fromAddress(req.address);
    for (trusted_proxies) |proxy| {
        if (!proxy.eql(peer)) continue;
        const forwarded = req.header("x-forwarded-for") orelse return peer;
        // The immediate trusted proxy sets or appends its direct client's IP.
        const start = if (std.mem.lastIndexOfScalar(u8, forwarded, ',')) |comma| comma + 1 else 0;
        return rate.ClientIp.parse(std.mem.trim(u8, forwarded[start..], " \t")) catch peer;
    }
    return peer;
}

fn persist(io: std.Io, path: []const u8, bytes: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFileAtomic(io, path, .{ .replace = true });
    defer file.deinit(io);
    try file.file.writeStreamingAll(io, bytes);
    try file.file.sync(io);
    try file.replace(io);
}

fn adminAsset(req: *httpz.Request, res: *httpz.Response) !bool {
    const Asset = struct { path: []const u8, body: []const u8, mime: []const u8 };
    const assets = [_]Asset{
        .{ .path = "/admin", .body = @embedFile("web/index.html"), .mime = "text/html; charset=utf-8" },
        .{ .path = "/admin/", .body = @embedFile("web/index.html"), .mime = "text/html; charset=utf-8" },
        .{ .path = "/admin/app.js", .body = @embedFile("web/app.js"), .mime = "text/javascript; charset=utf-8" },
        .{ .path = "/admin/json.js", .body = @embedFile("web/json.js"), .mime = "text/javascript; charset=utf-8" },
        .{ .path = "/admin/style.css", .body = @embedFile("web/style.css"), .mime = "text/css; charset=utf-8" },
    };
    for (assets) |asset| {
        if (!std.mem.eql(u8, req.url.path, asset.path)) continue;
        if (req.method != .GET and req.method != .HEAD) {
            res.header("Allow", "GET, HEAD");
            try reply(res, 405, "method not allowed");
        } else {
            res.header("Content-Type", asset.mime);
            res.header("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'; form-action 'none'");
            res.header("Referrer-Policy", "no-referrer");
            res.body = asset.body;
        }
        return true;
    }
    return false;
}

fn secureEqual(a: []const u8, b: []const u8) bool {
    const hash = std.crypto.hash.sha2.Sha256;
    var left: [hash.digest_length]u8 = undefined;
    var right: [hash.digest_length]u8 = undefined;
    hash.hash(a, &left, .{});
    hash.hash(b, &right, .{});
    return std.crypto.timing_safe.eql([hash.digest_length]u8, left, right);
}

fn json(res: *httpz.Response, value: anytype) !void {
    res.body = try std.json.Stringify.valueAlloc(res.arena, value, .{});
    res.content_type = .JSON;
}

fn reply(res: *httpz.Response, status: u16, message: []const u8) !void {
    res.status = status;
    try json(res, .{ .code = status, .message = message });
}

fn matches(spec: mock.Match, body: std.json.Value, req: *httpz.Request) !bool {
    if (spec.body) |expected| if (!mock.bodyMatches(expected, body)) return false;
    for (spec.headers) |pair| {
        const name = try std.ascii.allocLowerString(req.arena, pair.name);
        if (!std.mem.eql(u8, req.header(name) orelse return false, pair.value)) return false;
    }
    if (spec.query.len > 0) {
        const query = try req.query();
        for (spec.query) |pair| {
            if (!std.mem.eql(u8, query.get(pair.name) orelse return false, pair.value)) return false;
        }
    }
    return true;
}

fn cors(config: mock.Cors, req: *httpz.Request, res: *httpz.Response) !bool {
    res.header("Vary", "Origin, Access-Control-Request-Method, Access-Control-Request-Headers");
    const origin = req.header("origin") orelse return true;
    for (config.origins) |allowed| {
        if (std.mem.eql(u8, allowed, "*") or std.mem.eql(u8, origin, allowed)) {
            res.header("Access-Control-Allow-Origin", try res.arena.dupe(u8, allowed));
            return true;
        }
    }
    return false;
}

fn allowedHeaders(allowed: []const u8, requested: []const u8) bool {
    var requested_it = std.mem.splitScalar(u8, requested, ',');
    while (requested_it.next()) |raw| {
        const name = std.mem.trim(u8, raw, " \t");
        if (name.len == 0) continue;
        var allowed_it = std.mem.splitScalar(u8, allowed, ',');
        var found = false;
        while (allowed_it.next()) |candidate| {
            if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, candidate, " \t"), name)) found = true;
        }
        if (!found) return false;
    }
    return true;
}
