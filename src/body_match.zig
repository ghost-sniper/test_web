const std = @import("std");
const jsonpath = @import("jsonpath");
const xpath = @import("xpath");
const ztree = @import("ztree");
const regex = @import("regex");

const Allocator = std.mem.Allocator;
const Value = std.json.Value;
const max_expression_bytes = 1024;
const max_workspace_bytes = 16 * 1024 * 1024;
const max_json_depth = 128;

pub const Spec = struct {
    mode: enum { jsonpath, xpath, regex },
    expression: []const u8,
    expected: ?struct { value: Value } = null,
    namespaces: []const Namespace = &.{},
};

const Namespace = struct { prefix: []const u8, uri: []const u8 };

pub const Compiled = struct {
    program: union(enum) {
        jsonpath: jsonpath.model.JPQuery,
        xpath: *const xpath.Expr,
        regex: regex.Regexp,
    },
    expected: ?Value,

    pub fn init(arena: Allocator, allocator: Allocator, spec: Spec, is_xml: bool) !Compiled {
        if (spec.expression.len == 0 or spec.expression.len > max_expression_bytes) return error.InvalidBodyExpressionLength;
        if (spec.namespaces.len != 0 and spec.mode != .xpath) return error.UnexpectedXPathNamespaces;
        if (spec.expected != null and spec.mode == .regex) return error.UnexpectedRegexExpectedValue;
        const expected = if (spec.expected) |entry| entry.value else null;
        return .{
            .expected = expected,
            .program = switch (spec.mode) {
                .jsonpath => blk: {
                    if (is_xml) return error.JsonPathRequiresJson;
                    try validateJsonPathFunctions(spec.expression);
                    break :blk .{ .jsonpath = jsonpath.parser.parse(spec.expression, arena) catch |err| switch (err) {
                        error.OutOfMemory => return err,
                        else => return error.InvalidJsonPath,
                    } };
                },
                .xpath => blk: {
                    if (!is_xml) return error.XPathRequiresXml;
                    if (expected) |value| if (value != .string) return error.InvalidXPathExpectedValue;
                    for (spec.namespaces, 0..) |namespace, index| {
                        if (namespace.prefix.len == 0 or namespace.uri.len == 0 or
                            std.mem.indexOfAny(u8, namespace.prefix, ": \r\n\t") != null) return error.InvalidXPathNamespace;
                        for (spec.namespaces[0..index]) |previous| {
                            if (std.mem.eql(u8, namespace.prefix, previous.prefix)) return error.DuplicateXPathNamespace;
                        }
                    }
                    const resolver: xpath.NsResolver = .{ .ctx = &spec, .lookupFn = lookupNamespace };
                    break :blk .{ .xpath = xpath.compile(arena, spec.expression, resolver) catch |err| switch (err) {
                        error.OutOfMemory => return err,
                        else => return error.InvalidXPath,
                    } };
                },
                .regex => .{ .regex = regex.compile(allocator, spec.expression) catch |err| switch (err) {
                    error.OutOfMemory => return err,
                    else => return error.InvalidBodyRegex,
                } },
            },
        };
    }

    pub fn deinit(self: *Compiled) void {
        if (self.program == .regex) self.program.regex.deinit();
    }
};

fn lookupNamespace(context: ?*const anyopaque, prefix: []const u8) ?[]const u8 {
    const spec: *const Spec = @ptrCast(@alignCast(context.?));
    for (spec.namespaces) |binding| {
        if (std.mem.eql(u8, binding.prefix, prefix)) return binding.uri;
    }
    return null;
}

// Use the bounded regex engine for regular expressions, including when a body
// could supply the pattern through a JSONPath function argument.
fn validateJsonPathFunctions(source: []const u8) !void {
    var quote: ?u8 = null;
    var index: usize = 0;
    while (index < source.len) {
        const char = source[index];
        if (quote) |delimiter| {
            if (char == '\\' and index + 1 < source.len) index += 1;
            if (char == delimiter) quote = null;
        } else if (char == '"' or char == '\'') {
            quote = char;
        } else if (std.ascii.isAlphabetic(char) or char == '_') {
            const start = index;
            while (index + 1 < source.len and (std.ascii.isAlphanumeric(source[index + 1]) or source[index + 1] == '_')) index += 1;
            const tail = std.mem.trimStart(u8, source[index + 1 ..], " \t\r\n");
            if (std.mem.startsWith(u8, tail, "(")) {
                const name = source[start .. index + 1];
                if (std.mem.eql(u8, name, "match") or std.mem.eql(u8, name, "search")) return error.UnsupportedJsonPathRegexFunction;
                if (!std.mem.eql(u8, name, "length") and !std.mem.eql(u8, name, "count") and
                    !std.mem.eql(u8, name, "value")) return error.UnsupportedJsonPathFunction;
            }
        }
        index += 1;
    }
}

pub const Evaluation = struct {
    allocator: Allocator,
    raw: ?[]const u8,
    body: Value,
    checked_json: bool = false,
    document: ?*ztree.Document = null,
    workspace: ?std.heap.FixedBufferAllocator = null,
    document_end: usize = 0,

    pub fn deinit(self: *Evaluation) void {
        if (self.document) |document| document.destroy();
        if (self.workspace) |workspace| self.allocator.free(workspace.buffer);
    }

    fn scratch(self: *Evaluation) !Allocator {
        if (self.workspace == null) {
            self.workspace = .init(try self.allocator.alloc(u8, max_workspace_bytes));
        }
        const workspace = &self.workspace.?;
        // Keep the XML tree for later rules while recycling evaluation scratch.
        workspace.end_index = self.document_end;
        return workspace.allocator();
    }

    pub fn matches(self: *Evaluation, compiled: *const Compiled) !bool {
        const raw = self.raw orelse return false;
        if (raw.len == 0) return false;
        switch (compiled.program) {
            .jsonpath => |*query| {
                if (!self.checked_json) {
                    try checkJsonDepth(self.body, 0);
                    self.checked_json = true;
                }
                const allocator = try self.scratch();
                var iter = jsonpath.query.JsonPathIter.init(&self.body, allocator);
                defer iter.deinit();
                jsonpath.query.query(query, &iter) catch |err| return evaluationError(err);
                const expected = compiled.expected orelse return iter.cursors.items.len != 0;
                for (iter.cursors.items) |result| {
                    if (jsonSubset(expected, result.json.*) and jsonSubset(result.json.*, expected)) return true;
                }
                return false;
            },
            .xpath => |expression| {
                const allocator = try self.scratch();
                if (self.document == null) {
                    self.document = ztree.parse(allocator, raw, .{}) catch |err| return evaluationError(err);
                    self.document_end = self.workspace.?.end_index;
                }
                const document = self.document.?;
                var evaluator: xpath.Evaluator(error{}) = .init(allocator);
                const result = evaluator.eval(expression, .{ .node = document.ref(document.root) }) catch |err| return evaluationError(err);
                defer result.deinit(allocator);
                const expected = compiled.expected orelse return result.toBoolean();
                if (result == .node_set) {
                    for (result.node_set) |node| {
                        const value = node.stringValue(allocator) catch |err| return evaluationError(err);
                        defer allocator.free(value);
                        if (std.mem.eql(u8, value, expected.string)) return true;
                    }
                    return false;
                }
                const value = result.toString(allocator) catch |err| return evaluationError(err);
                defer allocator.free(value);
                return std.mem.eql(u8, value, expected.string);
            },
            .regex => |*pattern| {
                return pattern.matchString(self.allocator, raw);
            },
        }
    }
};

fn evaluationError(err: anyerror) error{ BodyExpressionLimit, InvalidBodyExpressionInput } {
    return switch (err) {
        error.OutOfMemory, error.RecursionLimit => error.BodyExpressionLimit,
        else => error.InvalidBodyExpressionInput,
    };
}

fn checkJsonDepth(value: Value, depth: usize) error{BodyExpressionLimit}!void {
    if (depth > max_json_depth) return error.BodyExpressionLimit;
    switch (value) {
        .array => |array| for (array.items) |child| try checkJsonDepth(child, depth + 1),
        .object => |object| for (object.values()) |child| try checkJsonDepth(child, depth + 1),
        else => {},
    }
}

/// Objects match recursively as subsets, while arrays and scalars match exactly.
pub fn jsonSubset(expected: Value, actual: Value) bool {
    if (std.meta.activeTag(expected) != std.meta.activeTag(actual)) return false;
    return switch (expected) {
        .null => true,
        .bool => |value| value == actual.bool,
        .integer => |value| value == actual.integer,
        .float => |value| value == actual.float,
        .string => |value| std.mem.eql(u8, value, actual.string),
        .number_string => |value| std.mem.eql(u8, value, actual.number_string),
        .array => |array| blk: {
            if (array.items.len != actual.array.items.len) break :blk false;
            for (array.items, actual.array.items) |left, right| {
                if (!jsonSubset(left, right)) break :blk false;
            }
            break :blk true;
        },
        .object => |object| blk: {
            var iter = object.iterator();
            while (iter.next()) |entry| {
                const value = actual.object.get(entry.key_ptr.*) orelse break :blk false;
                if (!jsonSubset(entry.value_ptr.*, value)) break :blk false;
            }
            break :blk true;
        },
    };
}
