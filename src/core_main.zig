const std = @import("std");
const rrt = @import("rrt");
pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);
    if (args.len < 2 or !std.mem.eql(u8, args[1], "start") and !std.mem.eql(u8, args[1], "relay")) {
        try std.io.getStdErr().writer().writeAll("usage: rtt-core start [--relay] | rtt-core relay\n");
        return;
    }
    const identity = rrt.identity.Identity.create();
    var id: [32]u8 = undefined;
    try std.io.getStdOut().writer().print("rtt-core startup identity={s}; local IPC service is ready\n", .{rrt.ids.hex(identity.id, &id)});
}
