# Ratcheted Rendezvous Transport implementation

RRT is a Zig 0.14.1 project with two build artifacts: `rtt-core` and `rtt-cli`. `build.zig` installs both executables and provides `run-core`, `run-cli`, `test`, and `fmt-check` build steps. The project uses only the Zig standard library cryptographic backend; compilation has no reduced-cryptography fallback.

## Modules

`src/crypto.zig` is the protocol cryptographic boundary. It exposes OS CSPRNG bytes, SHA-256, HMAC-SHA-256, HKDF-SHA-256, XChaCha20-Poly1305-IETF sealing and opening, Ed25519 signatures, and X25519 DH. The adapter rejects an all-zero X25519 result.

`src/ids.zig` creates 16-byte random identifiers and strict hexadecimal representations. `src/clock.zig` provides Unix milliseconds and a ten-minute protocol acceptance window. `src/config.zig` defines direct, relay, and privacy modes, the four permitted envelope classes, and validates traffic and batching bounds.

`src/identity.zig` constructs long-term Ed25519 identities. The identity ID is SHA-256 of the public signing key truncated to 16 bytes. Its safety-number routine domain-separates version 1 and sorted public keys, then produces eight zero-padded five-digit groups. `src/trust_store.zig` models peer states. Only `verified` permits application traffic; a different observed identity key changes a non-terminal peer to `changed`.

`src/handshake.zig` binds handshake bytes with `RRT-TRANSCRIPT-v1`, requires mode equality, and derives an initial root key from three DH outputs with `RRT-ROOT-v1`. `src/ratchet.zig` derives message and chain keys through HMAC-SHA-256 and erases live key material on close. `src/transparency.zig` implements linked, signed transparency-entry validation.

`src/envelopes.zig` creates and opens 1024-, 4096-, 16384-, and 65536-byte `RTE1` envelopes. The visible header carries routing data, random envelope ID, sequence, and nonce. Payload length, payload bytes, and random padding are inside authenticated ciphertext. `src/cover_traffic.zig` makes a constant number of decisions per privacy slot; data decisions replace cover decisions without increasing that number. `src/batching.zig` validates bounded batching windows.

## Executables

`rtt-core` currently exposes the local-engine process entry point and creates an in-memory identity for that process. `rtt-cli` owns no cryptographic state and reports `ERR_CORE_UNAVAILABLE` for commands needing a persistent core. Its `help` and `privacy-mode` paths print the fixed privacy limitation language.

The current implementation is intentionally limited to the tested protocol foundation. It does not persist identity material, expose a Unix-domain IPC service, operate network relays, generate or validate device certificates, or deliver application messages. Consequently it does not claim support for a deployed rendezvous service, a key archive, or completed command-line messaging workflow.

## Verification

`zig build test` runs deterministic unit coverage for AEAD/signature round trips, symmetric safety-number generation, fixed-size envelope parsing, handshake downgrade rejection, ratchet key consumption, peer key-change gating, and cover-traffic replacement. `zig build fmt-check` checks the source tree formatting.
