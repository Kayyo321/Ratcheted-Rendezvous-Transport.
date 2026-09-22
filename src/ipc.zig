const std = @import("std");
const crypto = @import("crypto.zig");
const encoding = @import("encoding.zig");
const errors = @import("errors.zig");

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

pub const Request = struct {
    request_id: u64,
    capability_proof: [32]u8,
    command: []const u8,
    payload: []const u8,
};

pub const Response = struct {
    request_id: u64,
    ok: bool,
    code: errors.Code,
    payload: []const u8,
};

pub fn capabilityProof(capability: crypto.Key, request_id: u64, command: []const u8, payload: []const u8) [32]u8 {
    var writer = encoding.Writer.init(std.heap.page_allocator);
    defer writer.deinit();
    writer.writeU64(request_id) catch unreachable;
    writer.bytes(command) catch unreachable;
    writer.bytes(payload) catch unreachable;
    return crypto.hmac(&capability, writer.list.items);
}

pub fn verifyCapability(request: Request, capability: crypto.Key) bool {
    const expected = capabilityProof(capability, request.request_id, request.command, request.payload);
    return std.crypto.timing_safe.eql(expected, request.capability_proof);
}

pub fn encodeRequest(allocator: std.mem.Allocator, request: Request) ![]u8 {
    var writer = encoding.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeU64(request.request_id);
    try writer.fixed(&request.capability_proof);
    try writer.bytes(request.command);
    try writer.bytes(request.payload);
    return writer.list.toOwnedSlice();
}

pub fn decodeRequest(bytes: []const u8) !Request {
    var reader = encoding.Reader.init(bytes);
    const id = try reader.readU64();
    const proof: [32]u8 = (try reader.fixed(32)).*;
    const command = try reader.bytes();
    const payload = try reader.bytes();
    try reader.finish();
    if (command.len == 0 or command.len > 128 or payload.len > max_payload_bytes) return error.BadFrame;
    return .{ .request_id = id, .capability_proof = proof, .command = command, .payload = payload };
}

pub fn encodeResponse(allocator: std.mem.Allocator, response: Response) ![]u8 {
    var writer = encoding.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeU64(response.request_id);
    try writer.writeU8(@intFromBool(response.ok));
    try writer.writeU8(@intFromEnum(response.code));
    try writer.bytes(response.payload);
    return writer.list.toOwnedSlice();
}

pub fn decodeResponse(bytes: []const u8) !Response {
    var reader = encoding.Reader.init(bytes);
    const id = try reader.readU64();
    const ok = try reader.readU8();
    if (ok > 1) return error.BadFrame;
    const code = std.meta.intToEnum(errors.Code, try reader.readU8()) catch return error.BadFrame;
    const payload = try reader.bytes();
    try reader.finish();
    return .{ .request_id = id, .ok = ok == 1, .code = code, .payload = payload };
}

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

test "IPC requests require the capability proof and reject trailing bytes" {
    const capability = [_]u8{9} ** 32;
    const proof = capabilityProof(capability, 7, "status", "{}");
    const encoded = try encodeRequest(std.testing.allocator, .{ .request_id = 7, .capability_proof = proof, .command = "status", .payload = "{}" });
    defer std.testing.allocator.free(encoded);
    const request = try decodeRequest(encoded);
    try std.testing.expect(verifyCapability(request, capability));
    try std.testing.expect(!verifyCapability(request, [_]u8{8} ** 32));
    var trailing: [encoded.len + 1]u8 = undefined;
    @memcpy(trailing[0..encoded.len], encoded);
    trailing[encoded.len] = 1;
    try std.testing.expectError(error.TrailingBytes, decodeRequest(&trailing));
}
