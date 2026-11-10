const std = @import("std");

pub const max_requests_per_second = 10_000;
const window_ns = std.time.ns_per_s;

pub const ClientIp = struct {
    bytes: [16]u8,

    pub fn fromAddress(address: std.Io.net.IpAddress) ClientIp {
        return .{ .bytes = switch (address) {
            .ip4 => |ip| [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff } ++ ip.bytes,
            .ip6 => |ip| ip.bytes,
        } };
    }

    pub fn parse(ip: []const u8) !ClientIp {
        return fromAddress(try std.Io.net.IpAddress.parse(ip, 0));
    }

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !ClientIp {
        const ip = try std.json.innerParse([]const u8, allocator, source, options);
        return parse(ip) catch error.InvalidCharacter;
    }

    pub fn eql(a: ClientIp, b: ClientIp) bool {
        return std.mem.eql(u8, &a.bytes, &b.bytes);
    }
};

pub const Policy = struct {
    requests_per_second: u32 = 0,
    clients: []const ClientLimit = &.{},

    pub const ClientLimit = struct { ip: ClientIp, requests_per_second: u32 };

    pub fn limitFor(self: Policy, client: ClientIp) u32 {
        for (self.clients) |entry| {
            if (entry.ip.eql(client)) return entry.requests_per_second;
        }
        return self.requests_per_second;
    }
};

/// Quotas are keyed by route and client. The application serializes access.
pub const RateLimiter = struct {
    buckets: std.AutoArrayHashMapUnmanaged(Key, Bucket) = .empty,
    allocated_slots: usize = 0,
    last_cleanup: ?i96 = null,

    // Reclaim expired entries without throwing out live quotas under load.
    const max_buckets = 4096;
    const max_slots = 1_000_000;
    const Key = struct { route: [32]u8, client: ClientIp };
    pub const Result = enum { allowed, limited, capacity };

    const Bucket = struct {
        times: []i96 = &.{},
        head: usize = 0,
        count: usize = 0,

        fn at(self: Bucket, index: usize) i96 {
            return self.times[(self.head + index) % self.times.len];
        }
    };

    pub fn deinit(self: *RateLimiter, allocator: std.mem.Allocator) void {
        for (self.buckets.values()) |bucket| allocator.free(bucket.times);
        self.buckets.deinit(allocator);
    }

    pub fn allow(self: *RateLimiter, allocator: std.mem.Allocator, io: std.Io, method: []const u8, path: []const u8, client: ClientIp, limit: u32) !Result {
        if (limit == 0) return .allowed;
        const Hash = std.crypto.hash.sha2.Sha256;
        var hash = Hash.init(.{});
        hash.update(method);
        hash.update("\x00");
        hash.update(path);
        return self.allowAt(allocator, .{ .route = hash.finalResult(), .client = client }, limit, std.Io.Clock.awake.now(io).nanoseconds);
    }

    fn allowAt(self: *RateLimiter, allocator: std.mem.Allocator, key: Key, limit: u32, now: i96) !Result {
        if (self.last_cleanup == null or now - self.last_cleanup.? >= window_ns) {
            var i = self.buckets.count();
            while (i > 0) {
                i -= 1;
                const bucket = self.buckets.values()[i];
                if (bucket.count == 0 or now - bucket.at(bucket.count - 1) >= window_ns) {
                    self.allocated_slots -= bucket.times.len;
                    allocator.free(bucket.times);
                    self.buckets.swapRemoveAt(i);
                }
            }
            self.last_cleanup = now;
        }
        if (self.buckets.count() >= max_buckets and !self.buckets.contains(key)) return .capacity;
        const entry = try self.buckets.getOrPut(allocator, key);
        const bucket = entry.value_ptr;
        if (!entry.found_existing) bucket.* = .{};
        while (bucket.count > 0 and now - bucket.at(0) >= window_ns) {
            bucket.head = (bucket.head + 1) % bucket.times.len;
            bucket.count -= 1;
        }
        if (bucket.count >= limit) return .limited;
        if (bucket.count == bucket.times.len) {
            const available = max_slots - self.allocated_slots;
            if (available == 0) return .capacity;
            const growth = @min(available, @max(bucket.times.len, 1), limit - bucket.times.len);
            const next = try allocator.alloc(i96, bucket.times.len + growth);
            for (next[0..bucket.count], 0..) |*time, i| time.* = bucket.at(i);
            allocator.free(bucket.times);
            bucket.times = next;
            bucket.head = 0;
            self.allocated_slots += growth;
        }
        bucket.times[(bucket.head + bucket.count) % bucket.times.len] = now;
        bucket.count += 1;
        return .allowed;
    }
};

test "rolling quotas isolate route and IP and use the current limit" {
    var limiter: RateLimiter = .{};
    const a = std.testing.allocator;
    defer limiter.deinit(a);
    const first = RateLimiter.Key{ .route = @splat(0), .client = try ClientIp.parse("192.0.2.1") };
    const another_ip = RateLimiter.Key{ .route = first.route, .client = try ClientIp.parse("192.0.2.2") };
    const another_route = RateLimiter.Key{ .route = @splat(1), .client = first.client };
    try std.testing.expect(first.client.eql(try ClientIp.parse("::ffff:192.0.2.1")));
    try std.testing.expectEqual(.allowed, try limiter.allowAt(a, first, 2, window_ns - 2));
    try std.testing.expectEqual(.allowed, try limiter.allowAt(a, first, 2, window_ns - 1));
    try std.testing.expectEqual(.limited, try limiter.allowAt(a, first, 2, window_ns));
    try std.testing.expectEqual(.allowed, try limiter.allowAt(a, another_ip, 2, window_ns));
    try std.testing.expectEqual(.allowed, try limiter.allowAt(a, another_route, 2, window_ns));
    try std.testing.expectEqual(.limited, try limiter.allowAt(a, first, 1, 2 * window_ns - 2));
    try std.testing.expectEqual(.allowed, try limiter.allowAt(a, first, 2, 2 * window_ns - 2));
    try std.testing.expectEqual(.limited, try limiter.allowAt(a, first, 2, 2 * window_ns - 2));
    try std.testing.expectEqual(.allowed, try limiter.allowAt(a, first, 2, 2 * window_ns - 1));
    try std.testing.expectEqual(.allowed, try limiter.allowAt(a, first, 2, 4 * window_ns));
    try std.testing.expectEqual(@as(usize, 1), limiter.buckets.count());
}
