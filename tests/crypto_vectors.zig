const std = @import("std");
const rrt = @import("../src/lib.zig");

test "sha256 adapter has the expected empty digest" {
    const digest = rrt.crypto.sha256("");
    var hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&hex, "{x}", .{digest}) catch unreachable;
    try std.testing.expectEqualStrings("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", &hex);
}
