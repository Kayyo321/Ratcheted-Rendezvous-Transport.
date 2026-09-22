const std = @import("std");
const crypto = @import("crypto.zig");

/// Authenticated encrypted record format. File replacement is intentionally
/// outside this codec so every record type uses the same bytes and can be
/// atomically written by its storage backend.
pub const magic = "RRS1";
pub const version: u8 = 1;
pub const header_bytes: usize = 4 + 1 + 24;
pub const tag_bytes: usize = 16;

pub fn seal(allocator: std.mem.Allocator, key: crypto.Key, plaintext: []const u8) ![]u8 {
    if (plaintext.len > 1024 * 1024) return error.RecordTooLarge;
    const result = try allocator.alloc(u8, header_bytes + plaintext.len + tag_bytes);
    errdefer allocator.free(result);
    @memcpy(result[0..4], magic);
    result[4] = version;
    var nonce: crypto.Nonce = undefined;
    crypto.randomBytes(&nonce);
    @memcpy(result[5..header_bytes], &nonce);
    const tag = try crypto.seal(key, nonce, result[0..header_bytes], plaintext, result[header_bytes .. result.len - tag_bytes]);
    @memcpy(result[result.len - tag_bytes ..], &tag);
    return result;
}

pub fn open(allocator: std.mem.Allocator, key: crypto.Key, record: []const u8) ![]u8 {
    if (record.len < header_bytes + tag_bytes or !std.mem.eql(u8, record[0..4], magic) or record[4] != version) return error.CorruptRecord;
    const plain_len = record.len - header_bytes - tag_bytes;
    if (plain_len > 1024 * 1024) return error.RecordTooLarge;
    const plaintext = try allocator.alloc(u8, plain_len);
    errdefer allocator.free(plaintext);
    const nonce: crypto.Nonce = record[5..header_bytes].*;
    const tag: crypto.Tag = record[record.len - tag_bytes ..].*;
    crypto.open(key, nonce, record[0..header_bytes], record[header_bytes .. record.len - tag_bytes], tag, plaintext) catch return error.CorruptRecord;
    return plaintext;
}

test "encrypted storage records authenticate their header and body" {
    const key = [_]u8{3} ** 32;
    const record = try seal(std.testing.allocator, key, "private state");
    defer std.testing.allocator.free(record);
    const plaintext = try open(std.testing.allocator, key, record);
    defer std.testing.allocator.free(plaintext);
    try std.testing.expectEqualStrings("private state", plaintext);
    record[4] ^= 1;
    try std.testing.expectError(error.CorruptRecord, open(std.testing.allocator, key, record));
}
