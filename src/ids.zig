const std = @import("std");
pub const Id = [16]u8;
pub fn random() Id {
    var id: Id = undefined;
    std.crypto.random.bytes(&id);
    return id;
}
pub fn hex(id: Id, out: *[32]u8) []const u8 {
    _ = std.fmt.bufPrint(out, "{x}", .{id}) catch unreachable;
    return out;
}
pub fn parse(value: []const u8) !Id {
    if (value.len != 32) return error.InvalidId;
    var id: Id = undefined;
    _ = try std.fmt.hexToBytes(&id, value);
    return id;
}
