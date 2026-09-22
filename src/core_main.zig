const std = @import("std");
const rrt = @import("rrt");
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2 or !std.mem.eql(u8, args[1], "start") and !std.mem.eql(u8, args[1], "relay")) {
        try std.Io.File.stderr().writeStreamingAll(io, "usage: rtt-core start [--relay] | rtt-core relay\n");
        return;
    }
    const identity = rrt.identity.Identity.create(io);
    var id: [32]u8 = undefined;
    var output: [128]u8 = undefined;
    const message = try std.fmt.bufPrint(&output, "rtt-core startup identity={s}; local IPC service is ready\n", .{rrt.ids.hex(identity.id, &id)});
    try std.Io.File.stdout().writeStreamingAll(io, message);
}
