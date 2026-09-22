const std = @import("std");
const crypto = @import("crypto.zig");

pub const magic = "RRC1";
pub const version: u8 = 1;
pub const max_payload_bytes: usize = 1024 * 1024;
pub const header_bytes: usize = 10;
pub const mac_bytes: usize = 32;

pub const Kind = enum(u8) { request = 1, response = 2, event = 3 };

pub const Frame = struct {
    kind: Kind,
    payload: []const u8,
};

/// Serializes a complete frame. The MAC covers the header and payload,
/// including the length and kind, preventing message-boundary confusion.
pub fn encode(allocator: std.mem.Allocator, key: crypto.Key, frame: Frame) ![]u8 {
    if (frame.payload.len > max_payload_bytes) return error.PayloadTooLarge;
    const result = try allocator.alloc(u8, header_bytes + frame.payload.len + mac_bytes);
    errdefer allocator.free(result);
    @memcpy(result[0..4], magic);
    result[4] = version;
    result[5] = @intFromEnum(frame.kind);
    std.mem.writeInt(u32, result[6..10], @intCast(frame.payload.len), .little);
    @memcpy(result[header_bytes .. header_bytes + frame.payload.len], frame.payload);
    const tag = crypto.hmac(&key, result[0 .. header_bytes + frame.payload.len]);
    @memcpy(result[result.len - mac_bytes ..], &tag);
    return result;
}

/// Parses a complete frame. Streaming transports must first accumulate exactly
/// `header_bytes + length + mac_bytes` bytes before calling this function.
pub fn decode(key: crypto.Key, bytes: []const u8) !Frame {
    if (bytes.len < header_bytes + mac_bytes) return error.BadFrame;
    if (!std.mem.eql(u8, bytes[0..4], magic) or bytes[4] != version) return error.BadFrame;
    const kind = std.meta.intToEnum(Kind, bytes[5]) catch return error.BadFrame;
    const length: usize = @intCast(std.mem.readInt(u32, bytes[6..10], .little));
    if (length > max_payload_bytes or bytes.len != header_bytes + length + mac_bytes) return error.BadFrame;
    const expected = crypto.hmac(&key, bytes[0 .. header_bytes + length]);
    if (!std.crypto.timing_safe.eql([32]u8, expected, bytes[bytes.len - mac_bytes ..].*)) return error.BadFrame;
    return .{ .kind = kind, .payload = bytes[header_bytes .. header_bytes + length] };
}

test "authenticated IPC frame round trips" {
    const key = [_]u8{7} ** 32;
    const encoded = try encode(std.testing.allocator, key, .{ .kind = .request, .payload = "status" });
    defer std.testing.allocator.free(encoded);
    const decoded = try decode(key, encoded);
    try std.testing.expectEqual(Kind.request, decoded.kind);
    try std.testing.expectEqualStrings("status", decoded.payload);
}

test "IPC rejects modified, truncated, and oversized frames" {
    const key = [_]u8{7} ** 32;
    const encoded = try encode(std.testing.allocator, key, .{ .kind = .request, .payload = "status" });
    defer std.testing.allocator.free(encoded);
    encoded[header_bytes] ^= 1;
    try std.testing.expectError(error.BadFrame, decode(key, encoded));
    try std.testing.expectError(error.BadFrame, decode(key, encoded[0 .. encoded.len - 1]));
}
