const std = @import("std");
pub const Writer = struct {
    list: std.ArrayList(u8),
    pub fn init(allocator: std.mem.Allocator) Writer {
        return .{ .list = std.ArrayList(u8).init(allocator) };
    }
    pub fn deinit(self: *Writer) void {
        self.list.deinit();
    }
    pub fn array(self: *Writer, n: u8) !void {
        if (n > 23) return error.Unsupported;
        try self.list.append(0x80 | n);
    }
    pub fn bytes(self: *Writer, value: []const u8) !void {
        if (value.len > 255) return error.Unsupported;
        try self.list.append(0x58);
        try self.list.append(@intCast(value.len));
        try self.list.appendSlice(value);
    }
    pub fn text(self: *Writer, value: []const u8) !void {
        if (value.len > 23) return error.Unsupported;
        try self.list.append(0x60 | @as(u8, @intCast(value.len)));
        try self.list.appendSlice(value);
    }
    pub fn uint(self: *Writer, value: u64) !void {
        if (value < 24) try self.list.append(@intCast(value)) else if (value <= 255) {
            try self.list.append(0x18);
            try self.list.append(@intCast(value));
        } else return error.Unsupported;
    }
};
test "canonical short array" {
    var w = Writer.init(std.testing.allocator);
    defer w.deinit();
    try w.array(2);
    try w.uint(1);
    try w.text("x");
    try std.testing.expectEqualSlices(u8, &.{ 0x82, 1, 0x61, 'x' }, w.list.items);
}
