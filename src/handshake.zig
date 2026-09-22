const std = @import("std");
const crypto = @import("crypto.zig");
const config = @import("config.zig");
pub const protocol_version: u16 = 1;
pub fn transcriptHash(hello: []const u8, welcome: []const u8) [32]u8 { var h = std.crypto.hash.sha2.Sha256.init(.{}); h.update("RRT-TRANSCRIPT-v1"); h.update(hello); h.update(welcome); var out: [32]u8 = undefined; h.final(&out); return out; }
pub fn validateMode(requested: config.Mode, selected: config.Mode) !void { if (requested != selected) return error.ModeDowngrade; }
pub fn rootKey(transcript: [32]u8, dh1: crypto.Key, dh2: crypto.Key, dh3: crypto.Key) crypto.Key { var ikm: [96]u8 = undefined; @memcpy(ikm[0..32], &dh1); @memcpy(ikm[32..64], &dh2); @memcpy(ikm[64..96], &dh3); var salt: [44]u8 = undefined; @memcpy(salt[0..12], "RRT-ROOT-v1"); @memcpy(salt[12..], &transcript); var out: crypto.Key = undefined; crypto.hkdf(&salt, &ikm, &out); return out; }
test "downgrades are rejected" { try std.testing.expectError(error.ModeDowngrade, validateMode(.privacy, .relay)); }
