const std = @import("std");
const crypto = @import("crypto.zig");
const ids = @import("ids.zig");
pub const Entry = struct { sequence: u64, identity_id: ids.Id, identity_pub: [32]u8, device_digest: [32]u8, previous_hash: [32]u8, timestamp_ms: u64, signature: [64]u8 };
pub fn hash(entry: Entry) [32]u8 { var h = std.crypto.hash.sha2.Sha256.init(.{}); h.update("RRT-TRANSPARENCY-v1"); h.update(std.mem.asBytes(&entry.sequence)); h.update(&entry.identity_id); h.update(&entry.identity_pub); h.update(&entry.device_digest); h.update(&entry.previous_hash); h.update(std.mem.asBytes(&entry.timestamp_ms)); var out: [32]u8 = undefined; h.final(&out); return out; }
pub fn verify(entry: Entry, operator_pub: [32]u8, previous: ?Entry) !void { if (previous) |p| { if (entry.sequence != p.sequence + 1 or !std.mem.eql(u8, &entry.previous_hash, &hash(p))) return error.InvalidChain; } try crypto.verify(operator_pub, &hash(entry), entry.signature); }
