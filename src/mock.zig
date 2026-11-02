const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = std.json.Value;

pub const Field = struct {
    name: []const u8,
    type: enum { string, integer, boolean, number },
    required: bool = false,
    default: ?Value = null,
};
pub const Request = struct {
    body_required: bool = false,
    fields: []const Field = &.{},
};
pub const Pair = struct { name: []const u8, value: []const u8 };
pub const Match = struct {
    body: ?Value = null,
    query: []const Pair = &.{},
    headers: []const Pair = &.{},
};
pub const Response = struct {
    status: u16 = 200,
    headers: []const Pair = &.{},
    body: Value,
    template: bool = false,
    delay_ms: u32 = 0,
};
pub const Rule = struct {
    id: []const u8,
    priority: i32 = 0,
    match: Match = .{},
    response: Response,
};
pub const Route = struct {
    method: []const u8,
    path: []const u8,
    request: Request = .{},
    rules: []const Rule,
};
pub const Cors = struct {
    origins: []const []const u8 = &.{"*"},
    allow_headers: []const u8 = "Content-Type, Authorization",
    max_age: u32 = 600,
};
pub const Config = struct {
    version: u8 = 1,
    cors: Cors = .{},
    routes: []const Route,
};

/// Owns the parsed tree; never references a request arena or the source buffer.
pub const Snapshot = struct {
    arena: std.heap.ArenaAllocator,
    config: Config,
    revision: [64]u8,
    source: []const u8,

    pub fn parse(allocator: Allocator, bytes: []const u8) !Snapshot {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const config = try std.json.parseFromSliceLeaky(Config, arena.allocator(), bytes, .{ .allocate = .alloc_always });
        try validate(config);
        return .{ .arena = arena, .config = config, .revision = digest(bytes), .source = try arena.allocator().dupe(u8, bytes) };
    }

    pub fn load(io: std.Io, allocator: Allocator, path: []const u8) !Snapshot {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(4 * 1024 * 1024));
        defer allocator.free(bytes);
        return parse(allocator, bytes);
    }

    pub fn deinit(self: *Snapshot) void {
        self.arena.deinit();
    }
};

pub fn digest(bytes: []const u8) [64]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    return std.fmt.bytesToHex(hash, .lower);
}

pub fn validMethod(method: []const u8) bool {
    inline for (.{ "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD" }) |m| {
        if (std.mem.eql(u8, method, m)) return true;
    }
    return false;
}

fn cleanHeader(value: []const u8) bool {
    for (value) |c| if (c < 32 or c == 127) return false;
    return true;
}

fn headerName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and std.mem.indexOfScalar(u8, "!#$%&'*+-.^_`|~", c) == null) return false;
    }
    return true;
}

fn validate(config: Config) !void {
    if (config.version != 1) return error.UnsupportedConfigVersion;
    if (config.routes.len > 1000) return error.TooManyRoutes;
    if (!cleanHeader(config.cors.allow_headers)) return error.InvalidCors;
    for (config.cors.origins) |origin| {
        if (origin.len == 0 or !cleanHeader(origin)) return error.InvalidCors;
        if (std.mem.eql(u8, origin, "*") and config.cors.origins.len != 1) return error.InvalidCors;
    }
    for (config.routes, 0..) |route, ri| {
        if (!validMethod(route.method)) return error.InvalidMethod;
        if (route.path.len == 0 or route.path[0] != '/' or std.mem.indexOfAny(u8, route.path, "?# \r\n\t") != null) return error.InvalidPath;
        if (std.mem.eql(u8, route.path, "/healthz") or std.mem.eql(u8, route.path, "/admin") or std.mem.startsWith(u8, route.path, "/admin/")) return error.ReservedPath;
        for (config.routes[0..ri]) |other| {
            if (std.mem.eql(u8, route.method, other.method) and std.mem.eql(u8, route.path, other.path)) return error.DuplicateRoute;
        }
        for (route.request.fields, 0..) |field, fi| {
            if (field.name.len == 0) return error.InvalidField;
            for (route.request.fields[0..fi]) |other| {
                if (std.mem.eql(u8, field.name, other.name)) return error.DuplicateField;
            }
            if (field.default) |value| {
                if (field.required or !isType(field, value)) return error.InvalidDefault;
            }
        }
        if (route.rules.len == 0 or route.rules.len > 1000) return error.InvalidRuleCount;
        for (route.rules, 0..) |rule, i| {
            if (rule.id.len == 0) return error.InvalidRuleId;
            for (route.rules[0..i]) |other| {
                if (std.mem.eql(u8, rule.id, other.id)) return error.DuplicateRuleId;
            }
            if (rule.match.body) |body| {
                if (body != .object) return error.InvalidBodyMatch;
            }
            for (rule.match.headers) |pair| {
                if (!headerName(pair.name) or !cleanHeader(pair.value)) return error.InvalidHeader;
            }
            for (rule.match.query) |pair| {
                if (pair.name.len == 0) return error.InvalidQuery;
            }
            const response = rule.response;
            if (response.status < 200 or response.status > 599) return error.InvalidStatus;
            if ((response.status == 204 or response.status == 205 or response.status == 304) and response.body != .null) return error.BodyNotAllowed;
            if (response.delay_ms > 30000) return error.DelayTooLong;
            if (response.headers.len > 32) return error.TooManyHeaders;
            for (response.headers, 0..) |pair, hi| {
                if (!headerName(pair.name) or !cleanHeader(pair.value)) return error.InvalidHeader;
                inline for (.{ "content-length", "transfer-encoding", "connection", "keep-alive", "upgrade", "trailer", "vary" }) |reserved| {
                    if (std.ascii.eqlIgnoreCase(pair.name, reserved)) return error.ReservedHeader;
                }
                if (std.ascii.startsWithIgnoreCase(pair.name, "access-control-")) return error.ReservedHeader;
                for (response.headers[0..hi]) |other| {
                    if (std.ascii.eqlIgnoreCase(pair.name, other.name)) return error.DuplicateHeader;
                }
            }
            if (response.template) try validateTemplateValue(response.body, route.request.fields);
        }
    }
}

fn isType(field: Field, value: Value) bool {
    return switch (field.type) {
        .string => value == .string,
        .integer => value == .integer,
        .boolean => value == .bool,
        .number => value == .integer or value == .float,
    };
}

pub fn parseBody(allocator: Allocator, spec: Request, raw: ?[]const u8) !Value {
    if (raw == null or raw.?.len == 0) {
        if (spec.body_required) return error.MissingBody;
    }
    var body: Value = if (raw) |bytes|
        if (bytes.len > 0) std.json.parseFromSliceLeaky(Value, allocator, bytes, .{ .allocate = .alloc_always }) catch return error.InvalidBody else .{ .object = .empty }
    else
        .{ .object = .empty };
    if (spec.fields.len > 0 and body != .object) return error.InvalidBody;
    for (spec.fields) |field| {
        if (body.object.get(field.name)) |value| {
            if (!isType(field, value)) return error.InvalidBody;
        } else if (field.default) |value| {
            try body.object.put(allocator, field.name, value);
        } else if (field.required) return error.InvalidBody;
    }
    return body;
}

/// Objects match recursively as subsets; arrays and scalar values match exactly.
pub fn bodyMatches(expected: Value, actual: Value) bool {
    if (std.meta.activeTag(expected) != std.meta.activeTag(actual)) return false;
    return switch (expected) {
        .null => true,
        .bool => |v| v == actual.bool,
        .integer => |v| v == actual.integer,
        .float => |v| v == actual.float,
        .string, .number_string => |v| std.mem.eql(u8, v, if (actual == .string) actual.string else actual.number_string),
        .array => |arr| blk: {
            if (arr.items.len != actual.array.items.len) break :blk false;
            for (arr.items, actual.array.items) |a, b| if (!bodyMatches(a, b)) break :blk false;
            break :blk true;
        },
        .object => |obj| blk: {
            var it = obj.iterator();
            while (it.next()) |entry| {
                const value = actual.object.get(entry.key_ptr.*) orelse break :blk false;
                if (!bodyMatches(entry.value_ptr.*, value)) break :blk false;
            }
            break :blk true;
        },
    };
}

const Expression = struct { name: []const u8, add: ?i64 };
fn expression(text: []const u8) !Expression {
    if (!std.mem.startsWith(u8, text, "body.")) return error.InvalidTemplate;
    const rest = text[5..];
    const separator = std.mem.indexOfScalar(u8, rest, '|');
    const name = rest[0 .. separator orelse rest.len];
    if (name.len == 0 or std.mem.indexOfAny(u8, name, "{}") != null) return error.InvalidTemplate;
    var add: ?i64 = null;
    if (separator) |index| {
        const op = rest[index + 1 ..];
        if (!std.mem.startsWith(u8, op, "add:")) return error.InvalidTemplate;
        add = std.fmt.parseInt(i64, op[4..], 10) catch return error.InvalidTemplate;
    }
    return .{ .name = name, .add = add };
}

fn validateTemplateValue(value: Value, fields: []const Field) anyerror!void {
    switch (value) {
        .string => |text| {
            var offset: usize = 0;
            while (std.mem.indexOfPos(u8, text, offset, "{{")) |start| {
                const end = std.mem.indexOfPos(u8, text, start + 2, "}}") orelse return error.InvalidTemplate;
                const expr = try expression(text[start + 2 .. end]);
                var found = false;
                for (fields) |field| {
                    if (!std.mem.eql(u8, field.name, expr.name)) continue;
                    if (!field.required and field.default == null) return error.OptionalTemplateField;
                    if (expr.add != null and field.type != .integer) return error.InvalidTemplateType;
                    found = true;
                }
                if (!found) return error.UnknownTemplateField;
                offset = end + 2;
            }
        },
        .array => |items| for (items.items) |item| try validateTemplateValue(item, fields),
        .object => |object| {
            var it = object.iterator();
            while (it.next()) |entry| try validateTemplateValue(entry.value_ptr.*, fields);
        },
        else => {},
    }
}

pub fn render(allocator: Allocator, value: Value, body: Value) anyerror!Value {
    return switch (value) {
        .string => |text| blk: {
            var out: std.Io.Writer.Allocating = .init(allocator);
            var offset: usize = 0;
            while (std.mem.indexOfPos(u8, text, offset, "{{")) |start| {
                try out.writer.writeAll(text[offset..start]);
                const end = std.mem.indexOfPos(u8, text, start + 2, "}}") orelse return error.InvalidTemplate;
                const expr = try expression(text[start + 2 .. end]);
                const input = if (body == .object) body.object.get(expr.name) orelse return error.InvalidBody else return error.InvalidBody;
                if (expr.add) |n| {
                    if (input != .integer) return error.InvalidBody;
                    const sum = std.math.add(i64, input.integer, n) catch return error.InvalidBody;
                    try out.writer.print("{d}", .{sum});
                } else if (input == .string) {
                    try out.writer.writeAll(input.string);
                } else {
                    try std.json.Stringify.value(input, .{}, &out.writer);
                }
                offset = end + 2;
            }
            try out.writer.writeAll(text[offset..]);
            break :blk .{ .string = try out.toOwnedSlice() };
        },
        .array => |items| blk: {
            var result = std.json.Array.init(allocator);
            for (items.items) |item| try result.append(try render(allocator, item, body));
            break :blk .{ .array = result };
        },
        .object => |object| blk: {
            var result: std.json.ObjectMap = .empty;
            var it = object.iterator();
            while (it.next()) |entry| try result.put(allocator, entry.key_ptr.*, try render(allocator, entry.value_ptr.*, body));
            break :blk .{ .object = result };
        },
        else => value,
    };
}

test "subset matching distinguishes types and array order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const expected = try std.json.parseFromSliceLeaky(Value, a, "{\"a\":{\"b\":1},\"c\":[1,2]}", .{});
    const actual = try std.json.parseFromSliceLeaky(Value, a, "{\"a\":{\"b\":1,\"x\":0},\"c\":[1,2],\"d\":true}", .{});
    try std.testing.expect(bodyMatches(expected, actual));
    try std.testing.expect(!bodyMatches(.{ .integer = 1 }, .{ .string = "1" }));
}

test "defaults, required fields, template escaping and overflow" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const spec: Request = .{ .body_required = true, .fields = &.{
        .{ .name = "name", .type = .string, .default = .{ .string = "" } },
        .{ .name = "age", .type = .integer, .default = .{ .integer = 0 } },
    } };
    try std.testing.expectError(error.MissingBody, parseBody(a, spec, null));
    try std.testing.expectError(error.InvalidBody, parseBody(a, spec, "{\"age\":\"1\"}"));
    const body = try parseBody(a, spec, "{\"name\":\"A\\\"B\"}");
    const rendered = try render(a, .{ .string = "{{body.name}}:{{body.age|add:1}}" }, body);
    try std.testing.expectEqualStrings("A\"B:1", rendered.string);
    const big = try parseBody(a, spec, "{\"age\":9223372036854775807}");
    try std.testing.expectError(error.InvalidBody, render(a, .{ .string = "{{body.age|add:1}}" }, big));
}

test "configuration rejects invalid status and unknown properties" {
    try std.testing.expectError(error.InvalidStatus, Snapshot.parse(std.testing.allocator,
        \\{"routes":[{"method":"GET","path":"/x","rules":[{"id":"x","response":{"status":999,"body":null}}]}]}
    ));
    try std.testing.expectError(error.UnknownField, Snapshot.parse(std.testing.allocator,
        \\{"routes":[],"typo":true}
    ));
}
