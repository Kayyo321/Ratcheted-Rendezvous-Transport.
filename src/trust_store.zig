const std = @import("std");
const ids = @import("ids.zig");

pub const State = enum { pending_verification, verified, changed, revoked, blocked };
pub const Peer = struct {
    identity_id: ids.Id,
    identity_public_key: [32]u8,
    state: State = .pending_verification,
    verified_at_ms: ?u64 = null,

    pub fn transition(self: *Peer, next: State, now_ms: u64) !void {
        const allowed = switch (self.state) {
            .pending_verification => next == .verified,
            .verified => next == .changed or next == .revoked or next == .blocked,
            .changed => next == .verified or next == .blocked,
            .revoked => next == .pending_verification,
            .blocked => next == .pending_verification,
        };
        if (!allowed) return error.InvalidTransition;
        self.state = next;
        self.verified_at_ms = if (next == .verified) now_ms else null;
    }

    pub fn permitsApplication(self: Peer) bool {
        return self.state == .verified;
    }
    pub fn observeKey(self: *Peer, public_key: [32]u8) void {
        if (!std.mem.eql(u8, &self.identity_public_key, &public_key) and self.state != .revoked and self.state != .blocked) self.state = .changed;
    }
    pub fn verify(self: *Peer, now_ms: u64) !void {
        try self.transition(.verified, now_ms);
    }
};

test "key replacement pauses a verified peer" {
    var p = Peer{ .identity_id = [_]u8{0} ** 16, .identity_public_key = [_]u8{1} ** 32, .state = .verified };
    p.observeKey([_]u8{2} ** 32);
    try std.testing.expectEqual(State.changed, p.state);
    try std.testing.expect(!p.permitsApplication());
}

test "trust transitions reject silent recovery" {
    var p = Peer{ .identity_id = [_]u8{0} ** 16, .identity_public_key = [_]u8{1} ** 32 };
    try p.verify(1);
    try p.transition(.revoked, 2);
    try std.testing.expectError(error.InvalidTransition, p.verify(3));
    try p.transition(.pending_verification, 4);
    try p.verify(5);
}
