const std = @import("std");
const xml = @import("xml");
const rate = @import("rate_limit.zig");
const Allocator = std.mem.Allocator;
const Value = std.json.Value;
const BodyFormat = enum { json, xml };

pub const Field = struct {
    name: []const u8,
    type: enum { string, integer, boolean, number },
    required: bool = false,
    default: ?Value = null,
};
pub const Request = struct {
    format: BodyFormat = .json,
    body_required: bool = false,
    fields: []const Field = &.{},
};
pub const Pair = struct { name: []const u8, value: []const u8 };
pub const Match = struct {
    body: ?Value = null,
    path: []const Pair = &.{},
    query: []const Pair = &.{},
    headers: []const Pair = &.{},
};
pub const Response = struct {
    format: BodyFormat = .json,
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
    folder_id: ?[]const u8 = null,
    rate_limit: rate.Policy = .{},
    request: Request = .{},
    rules: []const Rule,
};
pub const Folder = struct {
    id: []const u8,
    name: []const u8,
    parent_id: ?[]const u8 = null,
};
pub const Cors = struct {
    origins: []const []const u8 = &.{"*"},
    allow_headers: []const u8 = "Content-Type, Authorization",
    max_age: u32 = 600,
};
pub const Config = struct {
    version: u8 = 1,
    cors: Cors = .{},
    trusted_proxies: []const rate.ClientIp = &.{},
    folders: []const Folder = &.{},
    routes: []const Route,
};

/// Owns the parsed tree; never references a request arena or the source buffer.
pub const Snapshot = struct {
    arena: std.heap.ArenaAllocator,
    config: Config,
    revision: [64]u8,
    source: []const u8,
    viewer_catalog: []const u8,

    pub fn parse(allocator: Allocator, bytes: []const u8) !Snapshot {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const config = try std.json.parseFromSliceLeaky(Config, arena.allocator(), bytes, .{ .allocate = .alloc_always });
        try validate(config, allocator);
        const source = try arena.allocator().dupe(u8, bytes);
        const viewer_catalog = try buildViewerCatalog(config, arena.allocator());
        return .{ .arena = arena, .config = config, .revision = digest(bytes), .source = source, .viewer_catalog = viewer_catalog };
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

fn buildViewerCatalog(config: Config, allocator: Allocator) ![]const u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    var writer: std.json.Stringify = .{ .writer = &output.writer };
    try writer.beginObject();
    try writer.objectField("folders");
    try writer.write(config.folders);
    try writer.objectField("routes");
    try writer.beginArray();
    for (config.routes) |route| {
        try writer.write(.{
            .method = route.method,
            .path = route.path,
            .folder_id = route.folder_id,
            .request = route.request,
            .rules = route.rules,
        });
    }
    try writer.endArray();
    try writer.endObject();
    return output.toOwnedSlice();
}

pub fn isViewerPath(path: []const u8) bool {
    return std.mem.eql(u8, path, "/viewer") or std.mem.startsWith(u8, path, "/viewer/");
}

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

fn pathParameterName(segment: []const u8) ?[]const u8 {
    if (segment.len < 2 or segment[0] != '{' or segment[segment.len - 1] != '}') return null;
    return segment[1 .. segment.len - 1];
}

fn validPathParameterName(name: []const u8) bool {
    if (name.len == 0 or !(std.ascii.isAlphabetic(name[0]) or name[0] == '_')) return false;
    for (name[1..]) |char| {
        if (!std.ascii.isAlphanumeric(char) and char != '_') return false;
    }
    return true;
}

fn samePathShape(first: []const u8, second: []const u8) bool {
    var left = std.mem.splitScalar(u8, first, '/');
    var right = std.mem.splitScalar(u8, second, '/');
    while (left.next()) |segment| {
        const other = right.next() orelse return false;
        if (pathParameterName(segment) != null and pathParameterName(other) != null) continue;
        if (!std.mem.eql(u8, segment, other)) return false;
    }
    return right.next() == null;
}

fn matchPath(pattern: []const u8, path: []const u8) ?usize {
    if (std.mem.indexOfScalar(u8, pattern, '{') == null) {
        return if (std.mem.eql(u8, pattern, path)) 0 else null;
    }
    var segments = std.mem.splitScalar(u8, pattern, '/');
    var values = std.mem.splitScalar(u8, path, '/');
    var parameter_count: usize = 0;
    while (segments.next()) |segment| {
        const value = values.next() orelse return null;
        if (pathParameterName(segment) != null) {
            if (value.len == 0) return null;
            parameter_count += 1;
        } else if (!std.mem.eql(u8, segment, value)) {
            return null;
        }
    }
    return if (values.next() == null) parameter_count else null;
}

pub const MatchedRoute = struct {
    route: *const Route,
    parameter_count: usize,

    pub fn parameters(self: MatchedRoute, allocator: Allocator, path: []const u8) ![]const Pair {
        if (self.parameter_count == 0) return &.{};
        const result = try allocator.alloc(Pair, self.parameter_count);
        var segments = std.mem.splitScalar(u8, self.route.path, '/');
        var values = std.mem.splitScalar(u8, path, '/');
        var index: usize = 0;
        while (segments.next()) |segment| {
            const value = values.next().?;
            if (pathParameterName(segment)) |name| {
                result[index] = .{ .name = name, .value = try decodePathParameter(allocator, value) };
                index += 1;
            }
        }
        return result;
    }
};

pub fn findRoute(routes: []const Route, method: []const u8, path: []const u8) ?MatchedRoute {
    var best: ?MatchedRoute = null;
    for (routes) |*route| {
        if (!std.mem.eql(u8, route.method, method)) continue;
        const parameter_count = matchPath(route.path, path) orelse continue;
        const matched: MatchedRoute = .{ .route = route, .parameter_count = parameter_count };
        if (parameter_count == 0) return matched;
        if (best == null or parameter_count < best.?.parameter_count) best = matched;
    }
    return best;
}

fn decodePathParameter(allocator: Allocator, value: []const u8) ![]const u8 {
    const first_escape = std.mem.indexOfScalar(u8, value, '%') orelse return value;
    var offset = first_escape;
    while (std.mem.indexOfScalarPos(u8, value, offset, '%')) |index| {
        if (value.len - index < 3 or !std.ascii.isHex(value[index + 1]) or !std.ascii.isHex(value[index + 2])) {
            return error.InvalidPathEncoding;
        }
        offset = index + 3;
    }
    return std.Uri.percentDecodeInPlace(try allocator.dupe(u8, value));
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

fn validateFolders(config: Config, allocator: Allocator) !void {
    if (config.folders.len > 1000) return error.TooManyFolders;
    var by_id: std.StringHashMapUnmanaged(Folder) = .empty;
    defer by_id.deinit(allocator);
    for (config.folders, 0..) |folder, index| {
        if (folder.id.len == 0 or folder.id.len > 64) return error.InvalidFolderId;
        if (folder.name.len == 0 or folder.name.len > 256 or
            std.mem.trim(u8, folder.name, " \t\r\n").len != folder.name.len or
            std.mem.indexOfAny(u8, folder.name, "/\\\r\n") != null) return error.InvalidFolderName;
        const entry = try by_id.getOrPut(allocator, folder.id);
        if (entry.found_existing) return error.DuplicateFolderId;
        entry.value_ptr.* = folder;
        for (config.folders[0..index]) |other| {
            const same_parent = if (folder.parent_id) |parent|
                std.mem.eql(u8, parent, other.parent_id orelse "")
            else
                other.parent_id == null;
            if (same_parent and std.mem.eql(u8, folder.name, other.name)) return error.DuplicateFolderName;
        }
    }
    for (config.folders) |folder| {
        var parent = folder.parent_id;
        var depth: usize = 1;
        while (parent) |id| {
            if (std.mem.eql(u8, folder.id, id)) return error.FolderCycle;
            parent = (by_id.get(id) orelse return error.UnknownParentFolder).parent_id;
            depth += 1;
            if (depth > 16) return error.FolderDepthExceeded;
        }
    }
    for (config.routes) |route| {
        if (route.folder_id) |id| {
            if (!by_id.contains(id)) return error.UnknownRouteFolder;
        }
    }
}

fn validate(config: Config, allocator: Allocator) !void {
    if (config.version != 1) return error.UnsupportedConfigVersion;
    if (config.routes.len > 1000) return error.TooManyRoutes;
    try validateFolders(config, allocator);
    if (config.trusted_proxies.len > 32) return error.TooManyTrustedProxies;
    if (!cleanHeader(config.cors.allow_headers)) return error.InvalidCors;
    for (config.cors.origins) |origin| {
        if (origin.len == 0 or !cleanHeader(origin)) return error.InvalidCors;
        if (std.mem.eql(u8, origin, "*") and config.cors.origins.len != 1) return error.InvalidCors;
    }
    for (config.routes, 0..) |route, ri| {
        if (!validMethod(route.method)) return error.InvalidMethod;
        if (route.rate_limit.requests_per_second > rate.max_requests_per_second) return error.InvalidRequestsPerSecond;
        if (route.rate_limit.clients.len > 256) return error.TooManyClientLimits;
        for (route.rate_limit.clients, 0..) |client, ci| {
            if (client.requests_per_second > rate.max_requests_per_second) return error.InvalidRequestsPerSecond;
            for (route.rate_limit.clients[0..ci]) |previous| {
                if (client.ip.eql(previous.ip)) return error.DuplicateClientLimit;
            }
        }
        if (route.path.len == 0 or route.path[0] != '/' or std.mem.indexOfAny(u8, route.path, "?# \r\n\t") != null) return error.InvalidPath;
        if (std.mem.eql(u8, route.path, "/healthz") or std.mem.eql(u8, route.path, "/admin") or
            std.mem.startsWith(u8, route.path, "/admin/") or isViewerPath(route.path)) return error.ReservedPath;
        var path_names: std.StringHashMapUnmanaged(void) = .empty;
        defer path_names.deinit(allocator);
        var segments = std.mem.splitScalar(u8, route.path, '/');
        while (segments.next()) |segment| {
            const name = pathParameterName(segment) orelse continue;
            if (!validPathParameterName(name)) return error.InvalidPathParameter;
            const entry = try path_names.getOrPut(allocator, name);
            if (entry.found_existing) return error.DuplicatePathParameter;
        }
        for (config.routes[0..ri]) |other| {
            if (!std.mem.eql(u8, route.method, other.method)) continue;
            if (std.mem.eql(u8, route.path, other.path) or
                (path_names.count() > 0 and samePathShape(route.path, other.path))) return error.DuplicateRoute;
        }
        if (route.request.format == .xml and route.request.fields.len != 0) return error.XmlRequestFieldsUnsupported;
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
                switch (route.request.format) {
                    .json => if (body != .object) return error.InvalidBodyMatch,
                    .xml => {
                        if (body != .string) return error.InvalidBodyMatch;
                        try validateXml(allocator, body.string, null);
                    },
                }
            }
            for (rule.match.headers) |pair| {
                if (!headerName(pair.name) or !cleanHeader(pair.value)) return error.InvalidHeader;
            }
            for (rule.match.query) |pair| {
                if (pair.name.len == 0) return error.InvalidQuery;
            }
            for (rule.match.path, 0..) |pair, pi| {
                if (!path_names.contains(pair.name) or pair.value.len == 0) return error.InvalidPathMatch;
                for (rule.match.path[0..pi]) |previous| {
                    if (std.mem.eql(u8, previous.name, pair.name)) return error.DuplicatePathMatch;
                }
            }
            const response = rule.response;
            if (response.status < 200 or response.status > 599) return error.InvalidStatus;
            const body_forbidden = response.status == 204 or response.status == 205 or response.status == 304;
            if (body_forbidden and response.body != .null) return error.BodyNotAllowed;
            if (response.format == .xml) {
                if (!body_forbidden) {
                    if (response.body != .string) return error.InvalidXml;
                    try validateXml(allocator, response.body.string, if (response.template) route.request else null);
                }
            }
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
            if (response.template and response.format == .json) try validateTemplateValue(response.body, route.request);
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
    if (spec.format == .xml) {
        const body = raw orelse "";
        if (body.len == 0) return .null;
        try validateXml(allocator, body, null);
        return .{ .string = body };
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

fn validateXml(allocator: Allocator, document: []const u8, template_request: ?Request) !void {
    var parser: xml.Reader.Static = .init(allocator, document, .{ .updateLocation = null });
    defer parser.deinit();
    var depth: usize = 0;
    var placeholders: usize = 0;
    while (true) {
        const node = parser.interface.read() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidXml,
        };
        switch (node) {
            .eof => {
                if (template_request != null and placeholders != std.mem.count(u8, document, "{{")) {
                    return error.InvalidXmlTemplateContext;
                }
                return;
            },
            .element_start => {
                if (depth == 128) return error.InvalidXml;
                depth += 1;
                if (template_request) |request| {
                    for (0..parser.interface.attributeCount()) |index| {
                        const name = parser.interface.attributeName(index);
                        if (std.mem.eql(u8, name, "xmlns") or std.mem.startsWith(u8, name, "xmlns:")) continue;
                        placeholders += try validateTemplateText(parser.interface.attributeValueRaw(index), request);
                    }
                }
            },
            .element_end => depth -= 1,
            .text => if (template_request) |request| {
                placeholders += try validateTemplateText(parser.interface.textRaw(), request);
            },
            else => {},
        }
    }
}

fn xmlMatchText(document: []const u8) []const u8 {
    const bom = "\xef\xbb\xbf";
    const text = if (std.mem.startsWith(u8, document, bom)) document[bom.len..] else document;
    return std.mem.trim(u8, text, " \t\r\n");
}

fn nextXmlMatchByte(text: *[]const u8) ?u8 {
    if (text.len == 0) return null;
    const byte = text.*[0];
    text.* = text.*[1..];
    if (byte != '\r') return byte;
    if (text.len != 0 and text.*[0] == '\n') text.* = text.*[1..];
    return '\n';
}

pub fn requestBodyMatches(expected: Value, actual: Value) bool {
    if (expected != .string) return bodyMatches(expected, actual);
    if (actual != .string) return false;
    var pattern = xmlMatchText(expected.string);
    var document = xmlMatchText(actual.string);
    if (std.mem.eql(u8, pattern, document)) return true;
    while (nextXmlMatchByte(&pattern)) |byte| {
        if (nextXmlMatchByte(&document) != byte) return false;
    }
    return document.len == 0;
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

const Placeholder = struct {
    start: usize,
    end: usize,
    expr: Expression,

    fn next(text: []const u8, offset: usize) !?Placeholder {
        const start = std.mem.indexOfPos(u8, text, offset, "{{") orelse return null;
        const end = std.mem.indexOfPos(u8, text, start + 2, "}}") orelse return error.InvalidTemplate;
        return .{ .start = start, .end = end + 2, .expr = try expression(text[start + 2 .. end]) };
    }
};

fn validateTemplateText(text: []const u8, request: Request) !usize {
    var offset: usize = 0;
    var count: usize = 0;
    while (try Placeholder.next(text, offset)) |placeholder| {
        const expr = placeholder.expr;
        switch (request.format) {
            .json => {
                for (request.fields) |field| {
                    if (!std.mem.eql(u8, field.name, expr.name)) continue;
                    if (!field.required and field.default == null) return error.OptionalTemplateField;
                    if (expr.add != null and field.type != .integer) return error.InvalidTemplateType;
                    break;
                } else return error.UnknownTemplateField;
            },
            .xml => {
                var parts = std.mem.splitScalar(u8, expr.name, '.');
                while (parts.next()) |part| {
                    const attribute = std.mem.startsWith(u8, part, "@");
                    const name = if (attribute) part[1..] else part;
                    if (name.len == 0 or (attribute and parts.peek() != null) or
                        std.mem.indexOfAny(u8, name, "@ /\\\r\n\t<>&\"'") != null) return error.InvalidTemplate;
                }
            },
        }
        count += 1;
        offset = placeholder.end;
    }
    return count;
}

fn validateTemplateValue(value: Value, request: Request) anyerror!void {
    switch (value) {
        .string => |text| _ = try validateTemplateText(text, request),
        .array => |items| for (items.items) |item| try validateTemplateValue(item, request),
        .object => |object| {
            var it = object.iterator();
            while (it.next()) |entry| try validateTemplateValue(entry.value_ptr.*, request);
        },
        else => {},
    }
}

const XmlTemplateInput = struct {
    const Element = struct {
        attributes: std.StringHashMapUnmanaged([]const u8) = .empty,
        children: std.StringHashMapUnmanaged(*const Element) = .empty,
        text_start: usize,
        text_end: usize = 0,
    };

    root: Element,
    text: []const u8,

    fn parse(allocator: Allocator, document: []const u8) !XmlTemplateInput {
        var parser: xml.Reader.Static = .init(allocator, document, .{ .updateLocation = null });
        defer parser.deinit();
        try parser.interface.skipProlog();
        var text: std.Io.Writer.Allocating = .init(allocator);
        defer text.deinit();
        const root = try readElement(allocator, &parser.interface, &text);
        return .{ .root = root, .text = try text.toOwnedSlice() };
    }

    fn readElement(allocator: Allocator, reader: *xml.Reader, text: *std.Io.Writer.Allocating) anyerror!Element {
        var element: Element = .{ .text_start = text.written().len };
        for (0..reader.attributeCount()) |index| {
            const name = try allocator.dupe(u8, reader.attributeName(index));
            try element.attributes.put(allocator, name, try reader.attributeValueAlloc(allocator, index));
        }
        while (true) switch (try reader.read()) {
            .element_start => {
                const name = reader.elementName();
                if (element.children.contains(name)) {
                    try reader.readElementTextWrite(&text.writer);
                } else {
                    const key = try allocator.dupe(u8, name);
                    const child = try allocator.create(Element);
                    child.* = try readElement(allocator, reader, text);
                    try element.children.put(allocator, key, child);
                }
            },
            .element_end => {
                element.text_end = text.written().len;
                return element;
            },
            .text => try reader.textWrite(&text.writer),
            .cdata => try reader.cdataWrite(&text.writer),
            .character_reference => {
                var buffer: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(reader.characterReferenceChar(), &buffer) catch unreachable;
                try text.writer.writeAll(buffer[0..len]);
            },
            .entity_reference => try text.writer.writeAll(xml.predefined_entities.get(reader.entityReferenceName()).?),
            .comment, .pi => {},
            .eof, .xml_declaration => return error.InvalidBody,
        };
    }

    fn get(self: *const XmlTemplateInput, path: []const u8) ?[]const u8 {
        var element = &self.root;
        var parts = std.mem.splitScalar(u8, path, '.');
        while (parts.next()) |part| {
            if (std.mem.startsWith(u8, part, "@")) return element.attributes.get(part[1..]);
            element = element.children.get(part) orelse return null;
        }
        return self.text[element.text_start..element.text_end];
    }
};

const TemplateRender = struct {
    allocator: Allocator,
    body: Value,
    xml_input: ?XmlTemplateInput,
    escape_xml: bool,
    remaining: ?usize,

    fn append(self: *TemplateRender, writer: *std.Io.Writer, text: []const u8) !void {
        if (self.remaining) |*remaining| {
            if (text.len > remaining.*) return error.InvalidBody;
            remaining.* -= text.len;
        }
        try writer.writeAll(text);
    }

    fn appendXml(self: *TemplateRender, writer: *std.Io.Writer, text: []const u8) !void {
        var start: usize = 0;
        for (text, 0..) |char, index| {
            const entity = switch (char) {
                '&' => "&amp;",
                '<' => "&lt;",
                '>' => "&gt;",
                '"' => "&quot;",
                '\'' => "&apos;",
                '\t' => "&#9;",
                '\n' => "&#10;",
                '\r' => "&#13;",
                else => continue,
            };
            try self.append(writer, text[start..index]);
            try self.append(writer, entity);
            start = index + 1;
        }
        try self.append(writer, text[start..]);
    }

    fn renderText(self: *TemplateRender, text: []const u8) !Value {
        var placeholder = try Placeholder.next(text, 0) orelse return .{ .string = text };
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        defer out.deinit();
        var offset: usize = 0;
        while (true) {
            try self.append(&out.writer, text[offset..placeholder.start]);
            const expr = placeholder.expr;
            const input: Value = if (self.xml_input) |*document|
                .{ .string = document.get(expr.name) orelse return error.InvalidBody }
            else if (self.body == .object)
                self.body.object.get(expr.name) orelse return error.InvalidBody
            else
                return error.InvalidBody;
            if (expr.add) |amount| {
                const number = if (self.xml_input != null)
                    std.fmt.parseInt(i64, std.mem.trim(u8, input.string, " \t\r\n"), 10) catch return error.InvalidBody
                else if (input == .integer) input.integer else return error.InvalidBody;
                const sum = std.math.add(i64, number, amount) catch return error.InvalidBody;
                var buffer: [32]u8 = undefined;
                try self.append(&out.writer, std.fmt.bufPrint(&buffer, "{d}", .{sum}) catch unreachable);
            } else if (self.escape_xml) {
                const value = if (input == .string) input.string else try std.json.Stringify.valueAlloc(self.allocator, input, .{});
                try self.appendXml(&out.writer, value);
            } else if (input == .string) {
                try self.append(&out.writer, input.string);
            } else {
                try std.json.Stringify.value(input, .{}, &out.writer);
            }
            offset = placeholder.end;
            placeholder = try Placeholder.next(text, offset) orelse break;
        }
        try self.append(&out.writer, text[offset..]);
        return .{ .string = try out.toOwnedSlice() };
    }

    fn renderValue(self: *TemplateRender, value: Value) anyerror!Value {
        return switch (value) {
            .string => |text| self.renderText(text),
            .array => |items| blk: {
                var result = std.json.Array.init(self.allocator);
                for (items.items) |item| try result.append(try self.renderValue(item));
                break :blk .{ .array = result };
            },
            .object => |object| blk: {
                var result: std.json.ObjectMap = .empty;
                var it = object.iterator();
                while (it.next()) |entry| try result.put(self.allocator, entry.key_ptr.*, try self.renderValue(entry.value_ptr.*));
                break :blk .{ .object = result };
            },
            else => value,
        };
    }
};

pub fn render(allocator: Allocator, response: Response, request: Request, body: Value) !Value {
    var renderer: TemplateRender = .{
        .allocator = allocator,
        .body = body,
        .xml_input = if (request.format == .xml and body == .string) try XmlTemplateInput.parse(allocator, body.string) else null,
        .escape_xml = response.format == .xml,
        .remaining = if (request.format == .xml or response.format == .xml) 4 * 1024 * 1024 else null,
    };
    const rendered = try renderer.renderValue(response.body);
    if (response.format == .xml and rendered == .string) {
        validateXml(allocator, rendered.string, null) catch |err| switch (err) {
            error.InvalidXml => return error.InvalidBody,
            else => return err,
        };
    }
    return rendered;
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
    const rendered = try render(a, .{ .body = .{ .string = "{{body.name}}:{{body.age|add:1}}" } }, spec, body);
    try std.testing.expectEqualStrings("A\"B:1", rendered.string);
    const big = try parseBody(a, spec, "{\"age\":9223372036854775807}");
    try std.testing.expectError(error.InvalidBody, render(a, .{ .body = .{ .string = "{{body.age|add:1}}" } }, spec, big));
}

test "configuration rejects invalid status and unknown properties" {
    try std.testing.expectError(error.InvalidStatus, Snapshot.parse(std.testing.allocator,
        \\{"routes":[{"method":"GET","path":"/x","rules":[{"id":"x","response":{"status":999,"body":null}}]}]}
    ));
    try std.testing.expectError(error.UnknownField, Snapshot.parse(std.testing.allocator,
        \\{"routes":[],"typo":true}
    ));
}
