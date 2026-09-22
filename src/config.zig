pub const Mode = enum(u8) { direct = 0, relay = 1, privacy = 2 };
pub const Config = struct {
    privacy_mode: Mode = .relay,
    envelope_class: u32 = 4096,
    slot_interval_ms: u32 = 1000,
    envelopes_per_slot: u16 = 1,
    batch_min_ms: u32 = 0,
    batch_max_ms: u32 = 100,
    max_message_bytes: u32 = 1048576,
    relay_listen: []const u8 = "127.0.0.1:4400",
    pub fn valid(self: Config) bool {
        return (self.envelope_class == 1024 or self.envelope_class == 4096 or self.envelope_class == 16384 or self.envelope_class == 65536) and self.envelopes_per_slot > 0 and self.batch_min_ms <= self.batch_max_ms and self.batch_max_ms <= 10_000 and self.slot_interval_ms >= 100 and self.max_message_bytes > 0 and self.max_message_bytes <= 64 * 1024 * 1024;
    }
};
