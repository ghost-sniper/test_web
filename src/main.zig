const std = @import("std");
const httpz = @import("httpz");
const App = @import("app.zig").App;
const Snapshot = @import("mock.zig").Snapshot;

pub fn main(init: std.process.Init) !void {
    const env = init.environ_map;
    const host = env.get("MOCK_HOST") orelse "0.0.0.0";
    const port = try std.fmt.parseInt(u16, env.get("MOCK_PORT") orelse "9080", 10);
    if (port == 0) return error.InvalidPort;
    const path = env.get("MOCK_CONFIG") orelse "config/mock.json";
    const configured_token = env.get("MOCK_ADMIN_TOKEN") orelse "";
    var generated_token: [64]u8 = undefined;
    const token: []const u8 = if (configured_token.len == 0) blk: {
        var bytes: [32]u8 = undefined;
        try init.io.randomSecure(&bytes);
        generated_token = std.fmt.bytesToHex(bytes, .lower);
        break :blk &generated_token;
    } else blk: {
        if (configured_token.len < 16) return error.AdminTokenTooShort;
        break :blk configured_token;
    };
    var app = App{
        .io = init.io,
        .allocator = init.gpa,
        .config_path = path,
        .admin_token = token,
        .snapshot = Snapshot.load(init.io, init.gpa, path) catch |err| {
            std.log.err("cannot load {s}: {s}", .{ path, @errorName(err) });
            return err;
        },
    };
    defer app.snapshot.deinit();
    defer app.rate_limiter.deinit(init.gpa);
    var server = try httpz.Server(*App).init(init.io, init.gpa, .{
        .address = .{ .ip = try std.Io.net.IpAddress.parse(host, port) },
        .request = .{ .max_body_size = 4 * 1024 * 1024 },
        .response = .{ .max_header_count = 64 },
    }, &app);
    defer server.deinit();
    defer server.stop();

    if (configured_token.len == 0) std.debug.print("Generated admin token: {s}\n", .{token});
    std.log.info("Mock listening on {s}:{d}, config={s}", .{ host, port, path });
    try server.listen();
}

test {
    _ = @import("mock.zig");
    _ = @import("rate_limit.zig");
}
