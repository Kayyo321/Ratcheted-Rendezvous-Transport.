const errors = @import("errors.zig");

pub const version: u8 = 1;
pub const protocol_magic = "RRT1";
pub const ipc_magic = "RRC1";
pub const transcript_label = "RRT-TRANSCRIPT-v1";
pub const root_label = "RRT-ROOT-v1";
pub const safety_label = "RRT-SAFETY-v1";
pub const message_key_label = "RRT-MK-v1\x02";
pub const chain_key_label = "RRT-CK-v1\x01";

pub const max_frame_bytes: usize = 1024 * 1024;
pub const max_message_bytes: usize = 64 * 1024 * 1024;
pub const max_reassembly_bytes: usize = max_message_bytes;
pub const acceptance_window_ms: u64 = 10 * 60 * 1000;
pub const max_certificate_age_ms: u64 = 366 * 24 * 60 * 60 * 1000;

pub const EnvelopeClass = enum(u32) {
    one_kib = 1024,
    four_kib = 4096,
    sixteen_kib = 16384,
    sixty_four_kib = 65536,
};

pub const Mode = enum(u8) { direct = 0, relay = 1, privacy = 2 };

pub fn errorCode(err: anyerror) errors.Code {
    return switch (err) {
        error.ModeDowngrade => .ERR_MODE_DOWNGRADE,
        error.BadCertificate, error.BadIdentity, error.BadValidity, error.Expired => .ERR_BAD_CERTIFICATE,
        error.BadFrame, error.Truncated, error.TrailingBytes => .ERR_BAD_FRAME,
        error.InvalidEnvelope => .ERR_BAD_ENVELOPE,
        error.CorruptRecord => .ERR_STATE_CORRUPT,
        error.Replay => .ERR_REPLAY,
        else => .ERR_INVALID_ARGUMENT,
    };
}

test "protocol constants are stable" {
    try @import("std").testing.expectEqualStrings("RRT-TRANSCRIPT-v1", transcript_label);
    try @import("std").testing.expectEqual(@as(u32, 65536), @intFromEnum(EnvelopeClass.sixty_four_kib));
}
