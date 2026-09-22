# Implemented protocol components

The `crypto` module is the sole application-facing cryptographic adapter. It wraps `std.crypto.random`, SHA-256, HKDF-SHA-256, HMAC-SHA-256, XChaCha20-Poly1305-IETF, Ed25519, and X25519. X25519 shared secrets are rejected when all zero.

Identity IDs are the first 16 bytes of SHA-256 of the Ed25519 public key. Safety values bind both sorted identity public keys to version 1 using the `RRT-SAFETY-v1` domain separator. Eight five-digit decimal groups are produced from successive four-byte SHA-256 words. The resulting representation is symmetric for either peer.

Handshake helpers bind the byte-exact hello and welcome values with `RRT-TRANSCRIPT-v1`, reject a selected mode other than the requested mode, and derive a 32-byte root key from three X25519 values using HKDF-SHA-256 and `RRT-ROOT-v1`.

An envelope has a 72-byte visible header (`RTE1`, version, type, hop count, flags, route ID, envelope ID, sequence, and nonce), encrypted payload, and 16-byte tag. The payload begins with a little-endian 32-bit payload length, followed by payload bytes and cryptographically random authenticated padding. The header is AEAD associated data. Envelope creation and parsing reject unsupported classes.

The ratchet module derives message and chain keys using the `RRT-MK-v1` and `RRT-CK-v1` HMAC domain separators and securely clears live root and chain keys when a session closes. Transparency entries hash unsigned fields with `RRT-TRANSPARENCY-v1`, enforce monotonic linked sequences, and verify an Ed25519 operator signature.
