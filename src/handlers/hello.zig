const httpz = @import("httpz");
const std = @import("std");

const HelloRequest = struct {
    name: []const u8 = "",
    age: i64 = 0,
    email: []const u8 = "",
};

const HelloResponse = struct {
    message: []const u8,
    code: u16,
};

pub fn helloTest(req: *httpz.Request, res: *httpz.Response) !void {
    const raw = req.body() orelse {
        res.status = 400;
        try res.json(.{ .code = 400, .message = "missing request body" }, .{});
        return;
    };

    const parsed = std.json.parseFromSliceLeaky(HelloRequest, res.arena, raw, .{
        .ignore_unknown_fields = true,
    }) catch {
        res.status = 400;
        try res.json(.{ .code = 400, .message = "invalid JSON body" }, .{});
        return;
    };

    const message = try std.fmt.allocPrint(
        res.arena,
        "{s}明年这个时候你是{d}岁",
        .{ parsed.name, parsed.age + 1 },
    );

    try res.json(HelloResponse{ .message = message, .code = 200 }, .{});
}
