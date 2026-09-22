const std = @import("std");
pub const acceptance_window_ms: i64 = 10 * 60 * 1000;
pub fn nowMs() u64 {
    return @intCast(std.time.milliTimestamp());
}
pub fn acceptable(value: u64, now: u64) bool {
    const d: i128 = @as(i128, value) - @as(i128, now);
    return d >= -acceptance_window_ms and d <= acceptance_window_ms;
}
