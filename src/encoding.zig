const std = @import("std");

/// Canonical binary encoding used by persistent records and IPC payloads.
/// Integers are unsigned little-endian and variable-sized values carry a u32
/// length prefix. This module deliberately never allocates while decoding.
pub const max_value_bytes: usize = 1024 * 1024;

pub const Writer = struct {
    list: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Writer {
        return .{ .list = .init(allocator) };
    }
    pub fn deinit(self: *Writer) void {
        self.list.deinit();
    }
    pub fn writeU8(self: *Writer, value: u8) !void {
        try self.list.append(value);
    }
    pub fn writeU16(self: *Writer, value: u16) !void {
        var encoded: [2]u8 = undefined;
        std.mem.writeInt(u16, &encoded, value, .little);
        try self.list.appendSlice(&encoded);
    }
    pub fn writeU32(self: *Writer, value: u32) !void {
        var encoded: [4]u8 = undefined;
        std.mem.writeInt(u32, &encoded, value, .little);
        try self.list.appendSlice(&encoded);
    }
    pub fn writeU64(self: *Writer, value: u64) !void {
        var encoded: [8]u8 = undefined;
        std.mem.writeInt(u64, &encoded, value, .little);
        try self.list.appendSlice(&encoded);
    }
    pub fn bytes(self: *Writer, value: []const u8) !void {
        if (value.len > max_value_bytes or value.len > std.math.maxInt(u32)) return error.ValueTooLarge;
        try self.writeU32(@intCast(value.len));
        try self.list.appendSlice(value);
    }
    pub fn fixed(self: *Writer, value: []const u8) !void {
        try self.list.appendSlice(value);
    }
};

pub const Reader = struct {
    input: []const u8,
    at: usize = 0,

    pub fn init(input: []const u8) Reader {
        return .{ .input = input };
    }
    fn take(self: *Reader, count: usize) ![]const u8 {
        const end = std.math.add(usize, self.at, count) catch return error.Truncated;
        if (end > self.input.len) return error.Truncated;
        defer self.at = end;
        return self.input[self.at..end];
    }
    pub fn readU8(self: *Reader) !u8 {
        return (try self.take(1))[0];
    }
    pub fn readU16(self: *Reader) !u16 {
        return std.mem.readInt(u16, try self.take(2), .little);
    }
    pub fn readU32(self: *Reader) !u32 {
        return std.mem.readInt(u32, try self.take(4), .little);
    }
    pub fn readU64(self: *Reader) !u64 {
        return std.mem.readInt(u64, try self.take(8), .little);
    }
    pub fn fixed(self: *Reader, count: usize) ![]const u8 {
        return self.take(count);
    }
    pub fn bytes(self: *Reader) ![]const u8 {
        const count: usize = @intCast(try self.readU32());
        if (count > max_value_bytes) return error.ValueTooLarge;
        return self.take(count);
    }
    pub fn finish(self: Reader) !void {
        if (self.at != self.input.len) return error.TrailingBytes;
    }
};

test "canonical primitive encoding round trips" {
    var writer = Writer.init(std.testing.allocator);
    defer writer.deinit();
    try writer.writeU8(7);
    try writer.writeU16(0x1234);
    try writer.writeU32(0x89abcdef);
    try writer.writeU64(0x0123456789abcdef);
    try writer.bytes("rrt");
    var reader = Reader.init(writer.list.items);
    try std.testing.expectEqual(@as(u8, 7), try reader.readU8());
    try std.testing.expectEqual(@as(u16, 0x1234), try reader.readU16());
    try std.testing.expectEqual(@as(u32, 0x89abcdef), try reader.readU32());
    try std.testing.expectEqual(@as(u64, 0x0123456789abcdef), try reader.readU64());
    try std.testing.expectEqualStrings("rrt", try reader.bytes());
    try reader.finish();
}

test "decoder rejects truncation and trailing bytes" {
    var truncated = Reader.init(&.{ 1, 2, 3 });
    try std.testing.expectError(error.Truncated, truncated.readU32());
    var trailing = Reader.init(&.{ 1, 2 });
    _ = try trailing.readU8();
    try std.testing.expectError(error.TrailingBytes, trailing.finish());
}
