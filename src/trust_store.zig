const std = @import("std");
const ids = @import("ids.zig");

pub const State = enum { pending_verification, verified, changed, revoked, blocked };
pub const Peer = struct {
    identity_id: ids.Id,
    identity_public_key: [32]u8,
    state: State = .pending_verification,
    verified_at_ms: ?u64 = null,

    pub fn permitsApplication(self: Peer) bool {
        return self.state == .verified;
    }
    pub fn observeKey(self: *Peer, public_key: [32]u8) void {
        if (!std.mem.eql(u8, &self.identity_public_key, &public_key) and self.state != .revoked and self.state != .blocked) self.state = .changed;
    }
    pub fn verify(self: *Peer, now_ms: u64) !void {
        if (self.state == .revoked or self.state == .blocked) return error.NotVerifiable;
        self.state = .verified;
        self.verified_at_ms = now_ms;
    }
};

test "key replacement pauses a verified peer" {
    var p = Peer{ .identity_id = [_]u8{0} ** 16, .identity_public_key = [_]u8{1} ** 32, .state = .verified };
    p.observeKey([_]u8{2} ** 32);
    try std.testing.expectEqual(State.changed, p.state);
    try std.testing.expect(!p.permitsApplication());
}
