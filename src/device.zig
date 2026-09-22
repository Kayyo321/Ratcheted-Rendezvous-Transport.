const std = @import("std");
const crypto = @import("crypto.zig");
const ids = @import("ids.zig");

pub const Certificate = struct {
    device_id: ids.Id,
    signing_public_key: [32]u8,
    kex_public_key: [32]u8,
    generation: u32,
    not_before_ms: u64,
    not_after_ms: u64,
    identity_id: ids.Id,
    identity_public_key: [32]u8,
    signature: [64]u8,

    pub fn body(self: Certificate, out: *[16 + 32 + 32 + 4 + 8 + 8 + 16 + 32]u8) []const u8 {
        var at: usize = 0;
        @memcpy(out[at .. at + 16], &self.device_id);
        at += 16;
        @memcpy(out[at .. at + 32], &self.signing_public_key);
        at += 32;
        @memcpy(out[at .. at + 32], &self.kex_public_key);
        at += 32;
        std.mem.writeInt(u32, out[at .. at + 4], self.generation, .little);
        at += 4;
        std.mem.writeInt(u64, out[at .. at + 8], self.not_before_ms, .little);
        at += 8;
        std.mem.writeInt(u64, out[at .. at + 8], self.not_after_ms, .little);
        at += 8;
        @memcpy(out[at .. at + 16], &self.identity_id);
        at += 16;
        @memcpy(out[at .. at + 32], &self.identity_public_key);
        return out;
    }
    pub fn validate(self: Certificate, now_ms: u64) !void {
        if (!std.mem.eql(u8, &self.identity_id, &@import("identity.zig").identityId(self.identity_public_key))) return error.BadIdentity;
        if (self.not_after_ms < self.not_before_ms or self.not_after_ms - self.not_before_ms > 366 * 24 * 60 * 60 * 1000) return error.BadValidity;
        if (now_ms < self.not_before_ms or now_ms > self.not_after_ms) return error.Expired;
        var bytes: [148]u8 = undefined;
        try crypto.verify(self.identity_public_key, self.body(&bytes), self.signature);
    }
};
