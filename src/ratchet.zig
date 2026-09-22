const std = @import("std");
const crypto = @import("crypto.zig");

pub const Session = struct {
    root_key: crypto.Key,
    sending_chain: crypto.Key,
    receiving_chain: crypto.Key,
    send_number: u32 = 0,
    receive_number: u32 = 0,

    pub fn nextSendingKey(self: *Session) crypto.Key {
        const key = crypto.hmac(&self.sending_chain, "RRT-MK-v1\x02");
        self.sending_chain = crypto.hmac(&self.sending_chain, "RRT-CK-v1\x01");
        self.send_number += 1;
        return key;
    }
    pub fn close(self: *Session) void { std.crypto.secureZero(u8, &self.root_key); std.crypto.secureZero(u8, &self.sending_chain); std.crypto.secureZero(u8, &self.receiving_chain); }
};

test "a chain consumes distinct keys" { var s = Session{ .root_key = [_]u8{1} ** 32, .sending_chain = [_]u8{2} ** 32, .receiving_chain = [_]u8{3} ** 32 }; try std.testing.expect(!std.mem.eql(u8, &s.nextSendingKey(), &s.nextSendingKey())); s.close(); }
