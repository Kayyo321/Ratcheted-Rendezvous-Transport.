const std = @import("std");
const config = @import("config.zig");
pub const Decision = enum { cover, data, queued };
pub fn slotDecisions(mode: config.Mode, queued_messages: usize, per_slot: u16, out: []Decision) !usize {
    if (per_slot == 0 or out.len < per_slot) return error.InvalidConfig;
    if (mode != .privacy) return 0;
    var used: usize = 0;
    while (used < per_slot) : (used += 1) out[used] = if (used < queued_messages) .data else .cover;
    return used;
}
test "data replaces cover without changing slot count" {
    var slots: [2]Decision = undefined;
    try std.testing.expectEqual(@as(usize, 2), try slotDecisions(.privacy, 1, 2, &slots));
    try std.testing.expectEqual(Decision.data, slots[0]);
    try std.testing.expectEqual(Decision.cover, slots[1]);
}
