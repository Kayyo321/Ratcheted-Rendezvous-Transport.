const std = @import("std");
const rrt = @import("rrt");
const privacy_notice = "Messages are end-to-end encrypted. Privacy Mode reduces exposure of message size, timing, and network relationships, but it cannot guarantee anonymity against a global network observer or protect messages on a compromised device.\n";
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) {
        try std.Io.File.stdout().writeStreamingAll(io, "usage: rtt-cli COMMAND\n");
        std.process.exit(2);
    }
    if (std.mem.eql(u8, args[1], "privacy-mode") or std.mem.eql(u8, args[1], "help")) {
        try std.Io.File.stdout().writeStreamingAll(io, privacy_notice);
        return;
    }
    if (std.mem.eql(u8, args[1], "identity") and args.len == 3 and std.mem.eql(u8, args[2], "show")) {
        try std.Io.File.stdout().writeStreamingAll(io, "rtt-core unavailable (ERR_CORE_UNAVAILABLE)\n");
        std.process.exit(3);
    }
    _ = rrt;
    try std.Io.File.stdout().writeStreamingAll(io, "invalid command or unavailable core\n");
    std.process.exit(2);
}
