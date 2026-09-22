# Ratcheted Rendezvous Transport

RRT is an experimental Zig 0.14.1 cryptographic transport foundation. It implements OS-backed randomness, XChaCha20-Poly1305 authenticated encryption, X25519, Ed25519, HKDF-SHA-256, SHA-256 identifiers, fixed-size encrypted envelopes, identity safety numbers, peer verification state, transcript binding, and privacy-mode cover-slot selection.

This is research software. It makes no claim of anonymity, metadata freedom, production readiness, or protection from compromised endpoints or global observers.

## Build

Install Zig 0.14.1 and run:

```sh
zig build
zig build test
zig build fmt-check
```

The build produces `rtt-core` and `rtt-cli`. `rtt-core start` starts the current local-engine entry point. `rtt-cli help` prints the privacy warning; commands requiring a persisted local core return `ERR_CORE_UNAVAILABLE` rather than reading keys or state itself.

## Security model

Peers begin in `pending_verification`. Application traffic is permitted only for `verified` peers. Observing a changed identity key transitions a non-terminal peer to `changed`, which pauses application traffic. `revoked` and `blocked` peers cannot be verified through the ordinary verification operation.

Privacy-mode slot scheduling always emits the configured number of envelope decisions: queued data occupies slots first and cover traffic fills the rest. This makes real data replace cover traffic rather than add packets. Fixed envelope classes are 1024, 4096, 16384, and 65536 bytes; only these sizes are accepted.

The implementation has no persistent state store, relay transport, local IPC server, device-certificate persistence, or end-to-end command workflow yet. It therefore does not create private-key files, transmit messages, or provide a relay deployment path.
