const std = @import("std");
const crypto = @import("crypto.zig");
const ids = @import("ids.zig");
const clock = @import("clock.zig");
pub const Identity = struct {
    id: ids.Id,
    signing: crypto.SigningKeyPair,
    created_at_ms: u64,
    generation: u32 = 1,
    pub fn create() Identity {
        const kp = crypto.SigningKeyPair.generate();
        const id = identityId(kp.public_key.toBytes());
        return .{ .id = id, .signing = kp, .created_at_ms = clock.nowMs() };
    }
};
pub fn identityId(public_key: [32]u8) ids.Id {
    const d = crypto.sha256(&public_key);
    return d[0..16].*;
}
pub fn safety(local: [32]u8, peer: [32]u8, out: *[47]u8) void {
    var data: [13 + 2 + 64]u8 = undefined;
    @memcpy(data[0..13], "RRT-SAFETY-v1");
    std.mem.writeInt(u16, data[13..15], 1, .little);
    const less = std.mem.order(u8, &local, &peer) == .lt;
    @memcpy(data[15..47], if (less) &local else &peer);
    @memcpy(data[47..79], if (less) &peer else &local);
    const d = crypto.sha256(&data);
    var at: usize = 0;
    for (0..8) |group| {
        const n = (@as(u64, d[group * 4]) << 24 | @as(u64, d[group * 4 + 1]) << 16 | @as(u64, d[group * 4 + 2]) << 8 | d[group * 4 + 3]) % 100000;
        _ = std.fmt.bufPrint(out[at .. at + 5], "{d:0>5}", .{n}) catch unreachable;
        at += 5;
        if (group != 7) {
            out[at] = ' ';
            at += 1;
        }
    }
}
test "safety is symmetric" {
    const a = Identity.create();
    const b = Identity.create();
    var x: [47]u8 = undefined;
    var y: [47]u8 = undefined;
    safety(a.signing.public_key.toBytes(), b.signing.public_key.toBytes(), &x);
    safety(b.signing.public_key.toBytes(), a.signing.public_key.toBytes(), &y);
    try std.testing.expectEqualSlices(u8, &x, &y);
}
