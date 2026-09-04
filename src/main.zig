const std = @import("std");
const httpz = @import("httpz");
const handlers = @import("handlers");

const port = 9080;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var server = try httpz.Server(void).init(init.io, allocator, .{
        .address = .all(port),
    }, {});
    defer server.deinit();
    defer server.stop();

    var router = try server.router(.{});
    router.post("/hello/test", handlers.helloTest, .{});

    std.log.info("listening on http://0.0.0.0:{d}  (POST /hello/test)", .{port});
    try server.listen();
}
