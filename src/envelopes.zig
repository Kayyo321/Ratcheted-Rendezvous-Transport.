const std = @import("std");
const crypto = @import("crypto.zig");
const ids = @import("ids.zig");
pub const classes = [_]usize{ 1024, 4096, 16384, 65536 };
pub const Type = enum(u8) { cover = 0, data = 1, ack = 2, relay = 3 };
pub fn supported(n: usize) bool {
    for (classes) |c| if (c == n) return true;
    return false;
}
pub fn create(allocator: std.mem.Allocator, size: usize, kind: Type, route: ids.Id, sequence: u64, key: crypto.Key, payload: []const u8) ![]u8 {
    if (!supported(size) or size < 88 or payload.len + 4 > size - 72 - 16) return error.InvalidEnvelope;
    var out = try allocator.alloc(u8, size);
    errdefer allocator.free(out);
    @memcpy(out[0..4], "RTE1");
    out[4] = 1;
    out[5] = @intFromEnum(kind);
    out[6] = 0;
    out[7] = 0;
    @memcpy(out[8..24], &route);
    const eid = ids.random();
    @memcpy(out[24..40], &eid);
    std.mem.writeInt(u64, out[40..48], sequence, .little);
    var nonce: crypto.Nonce = undefined;
    crypto.randomBytes(&nonce);
    @memcpy(out[48..72], &nonce);
    var plain = try allocator.alloc(u8, size - 72 - 16);
    defer allocator.free(plain);
    std.mem.writeInt(u32, plain[0..4], @intCast(payload.len), .little);
    @memcpy(plain[4 .. 4 + payload.len], payload);
    crypto.randomBytes(plain[4 + payload.len ..]);
    const tag = try crypto.seal(key, nonce, out[0..48], plain, out[72 .. size - 16]);
    @memcpy(out[size - 16 ..], &tag);
    return out;
}
pub fn open(key: crypto.Key, envelope: []const u8, out: []u8) ![]const u8 {
    if (!supported(envelope.len) or !std.mem.eql(u8, envelope[0..4], "RTE1") or envelope[4] != 1 or out.len != envelope.len - 88) return error.InvalidEnvelope;
    const nonce = envelope[48..72].*;
    const tag = envelope[envelope.len - 16 ..].*;
    try crypto.open(key, nonce, envelope[0..48], envelope[72 .. envelope.len - 16], tag, out);
    const len = std.mem.readInt(u32, out[0..4], .little);
    if (len > out.len - 4) return error.InvalidEnvelope;
    return out[4 .. 4 + len];
}
test "fixed envelope conceals payload length" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var key: crypto.Key = undefined;
    crypto.randomBytes(&key);
    const e = try create(gpa.allocator(), 1024, .data, ids.random(), 1, key, "hi");
    defer gpa.allocator().free(e);
    var p: [936]u8 = undefined;
    try std.testing.expectEqualStrings("hi", try open(key, e, &p));
}
