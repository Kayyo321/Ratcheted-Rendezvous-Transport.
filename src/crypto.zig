const std = @import("std");
const crypto = std.crypto;
pub const Key = [32]u8;
pub const Nonce = [24]u8;
pub const Tag = [16]u8;
pub fn randomBytes(out: []u8) void {
    crypto.random.bytes(out);
}
pub fn sha256(data: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(data, &out, .{});
    return out;
}
pub fn hkdf(salt: []const u8, ikm: []const u8, out: []u8) void {
    const k = crypto.kdf.hkdf.HkdfSha256.extract(salt, ikm);
    crypto.kdf.hkdf.HkdfSha256.expand(out, "", k);
}
pub fn hmac(key: []const u8, data: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    var h = crypto.auth.hmac.sha2.HmacSha256.init(key);
    h.update(data);
    h.final(&out);
    return out;
}
pub fn seal(key: Key, nonce: Nonce, aad: []const u8, plain: []const u8, out: []u8) !Tag {
    if (out.len != plain.len) return error.Length;
    var tag: Tag = undefined;
    crypto.aead.chacha_poly.XChaCha20Poly1305.encrypt(out, &tag, plain, aad, nonce, key);
    return tag;
}
pub fn open(key: Key, nonce: Nonce, aad: []const u8, cipher: []const u8, tag: Tag, out: []u8) !void {
    if (out.len != cipher.len) return error.Length;
    try crypto.aead.chacha_poly.XChaCha20Poly1305.decrypt(out, cipher, tag, aad, nonce, key);
}
pub const SigningKeyPair = crypto.sign.Ed25519.KeyPair;
pub fn sign(pair: SigningKeyPair, msg: []const u8) ![64]u8 {
    return (try crypto.sign.Ed25519.sign(pair, msg, null)).toBytes();
}
pub fn verify(public_key_bytes: [32]u8, msg: []const u8, sig: [64]u8) !void {
    try crypto.sign.Ed25519.verify(crypto.sign.Ed25519.Signature.fromBytes(sig), msg, try crypto.sign.Ed25519.PublicKey.fromBytes(public_key_bytes));
}
pub const KexKeyPair = crypto.dh.X25519.KeyPair;
pub fn dh(secret: [32]u8, public: [32]u8) !Key {
    const out = try crypto.dh.X25519.scalarmult(secret, public);
    if (std.mem.allEqual(u8, &out, 0)) return error.WeakKey;
    return out;
}
test "aead and signatures round-trip" {
    const pair = SigningKeyPair.generate(std.testing.io);
    const msg = "rrt";
    const sig = try sign(pair, msg);
    try verify(pair.public_key.toBytes(), msg, sig);
    var key: Key = undefined;
    var nonce: Nonce = undefined;
    randomBytes(&key);
    randomBytes(&nonce);
    var c: [3]u8 = undefined;
    const tag = try seal(key, nonce, "a", msg, &c);
    var p: [3]u8 = undefined;
    try open(key, nonce, "a", &c, tag, &p);
    try std.testing.expectEqualStrings(msg, &p);
}
