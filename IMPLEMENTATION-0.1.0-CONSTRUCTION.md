# RRT 0.1.0 construction specification

> This is a temporary implementation document. It is intentionally untracked by Git. After every requirement below is implemented, tested, and reflected in the permanent project documentation, delete this file. Do not leave this file in the repository for the 0.1.0 release.

## 1. Exact objective

Turn the current cryptographic PoC into the first usable RRT implementation described by `PROJECT.md`. Do not call the work complete because helper functions compile. Completion requires a persistent local core, verified peer messaging, restart recovery, direct transport, relay transport, privacy-mode transport, and automated negative tests.

Keep Zig 0.14.1 and the existing cryptographic choices: OS randomness, Ed25519, X25519, XChaCha20-Poly1305-IETF, SHA-256, HMAC-SHA-256, and HKDF-SHA-256. Keep the existing identity IDs, safety-number derivation, envelope classes, transcript binding, ratchet rules, and trust states. Do not add plaintext fallbacks, trust-on-first-use, silent key replacement, or silent mode downgrade.

## 2. Product boundary

`rtt-core` owns all private keys, trust decisions, sessions, ratchets, storage, timers, network connections, and relay behavior. `rtt-cli` is only a local client. The CLI must never open private-key files, decrypt session state, or decide whether a peer is trusted.

Create a versioned framed local IPC service over a Unix-domain socket on Unix-like systems and a named pipe on Windows. The core must enforce security rules even if another IPC client is used.

## 3. Persistent data

Use `--data-dir`; if absent, use the platform per-user application-data directory. Never use the repository directory. Refuse an invalid or overly public data directory.

Create these records:

```text
version
identity.key                 encrypted private identity record
identity.public              public identity record
devices/<device-id>.key      encrypted private device keys
devices/<device-id>.cert     signed device certificate
peers/<identity-id>.peer     encrypted trust record
sessions/<session-id>.state  encrypted ratchet/session state
messages/inbox/<id>.msg      encrypted received message
messages/outbox/<id>.msg     encrypted outgoing message
transparency/<log-id>.state  encrypted checkpoint
audit/events.log             metadata-only security events
```

Private and mutable records must be encrypted. Write each replacement to a temporary sibling, flush it, atomically rename it, and flush the containing directory when supported. A crash must leave the old complete record or the new complete record, never a partial record.

The audit log may contain timestamps, event types, local/peer identity IDs, session IDs, and result codes. It must never contain private keys, plaintext, safety numbers, message keys, raw envelopes, or complete network addresses.

## 4. Identity and devices

The persistent identity record must contain magic `RRI1`, record version, identity public key, identity ID, encrypted private signing key, creation time, active status, random nonce, and authentication tag. Derive encryption from a user unlock secret using a memory-hard KDF through the crypto boundary. Never store the secret. Plaintext key storage is allowed only in an explicitly named development-only build mode; normal 0.1.0 builds must refuse it.

Create one device at initialization. Each device has a random stable device ID, Ed25519 signing key, X25519 key-agreement key, certificate generation, validity interval no longer than 366 days, issuing identity ID, and identity signature over a canonical fixed-order certificate body. Reject bad signatures, identity mismatches, duplicate fields, invalid lengths, expired certificates, overlong validity, and lower generations.

## 5. Canonical encoding and IPC

Implement one canonical encoder/decoder in `src/encoding.zig`. Use fixed field order, unsigned little-endian integers, and four-byte length-prefixed byte strings. Reject truncation, trailing bytes in complete records, overflow, duplicate fields, invalid enum values, and oversized allocations before allocating.

Each IPC frame is: magic `RRC1`; version byte `1`; kind byte (`request`, `response`, or `event`); four-byte payload length; payload; 32-byte MAC. Maximum payload is 1 MiB. Authenticate each connection using local OS credentials and a core challenge. If local credentials are unavailable, use a random restrictive-permission token that is not placed in process arguments.

Implement core commands for status, identity initialization/showing, peer add/show/verify/block/unblock, session start/close, message send/list/read, QR generation, and transparency status. Return stable errors including `ERR_LOCKED`, `ERR_UNVERIFIED_PEER`, `ERR_CHANGED_IDENTITY`, `ERR_REVOKED_PEER`, `ERR_BLOCKED_PEER`, `ERR_MODE_DOWNGRADE`, `ERR_BAD_FRAME`, `ERR_BAD_ENVELOPE`, `ERR_BAD_CERTIFICATE`, `ERR_SESSION_CLOSED`, `ERR_STORAGE`, `ERR_NETWORK`, and `ERR_RATE_LIMITED`.

## 6. Trust and verification

New peers always start as `pending_verification`. Keep exactly these states: `pending_verification`, `verified`, `changed`, `revoked`, `blocked`.

Use the existing symmetric `RRT-SAFETY-v1` safety number with eight five-digit groups. Verification requires the complete safety number or a complete QR scan. A QR payload uses magic `RQV1` and contains protocol version, identity ID, identity public key, current device certificate, safety-number version, and canonical checksum. The core must validate all of these and the expected contact identity.

Allowed transitions are:

```text
new -> pending_verification
pending_verification -> verified       explicit verification only
verified -> changed                    identity/device/certificate change
verified -> revoked                    verified revocation only
verified -> blocked                    explicit local block only
changed -> verified                    fresh explicit verification only
changed -> blocked                     explicit block
revoked -> pending_verification        fresh recovery/re-verification only
blocked -> pending_verification        explicit unblock only
```

Before verification, permit only limited identity discovery and handshake metadata. Do not display incoming application plaintext, deliver outgoing application plaintext, or advance the normal application ratchet. There must be no hidden bypass or one-click trust action.

On identity key, device key, or certificate-generation change, atomically mark the peer `changed`, close every session, clear live ratchet keys, retain old public verification data, and show the key-change warning. A new session requires fresh verification.

## 7. Handshake and ratchet

The handshake must include protocol version, both identity IDs and public keys, both device certificates, expected peer identity, selected mode, supported envelope classes, supported cover profiles, fresh nonces, and ephemeral X25519 public keys. Sign the canonical transcript.

Bind protocol version, identity keys, certificates, ephemeral keys, selected mode, envelope class, cover profile, relay-path identifier, and both nonces into the transcript. Reject any selected-mode mismatch as `ERR_MODE_DOWNGRADE`. A mode change requires a user-started new session.

Retain the three-DH root derivation, additionally bind verified identity keys, certificate generations, and transcript hash through HKDF context. Use independent sending and receiving chains. Permit a skipped-key window of 128 messages; reject larger gaps. Persist ratchet advancement before acknowledging a received message. Clear all live root, chain, message, and skipped keys after use or close.

## 8. Messages and envelopes

The encrypted message payload uses magic `RRM1` and contains random message ID, sender identity/device IDs, session ID, sender sequence, creation time, message type `text`, UTF-8 bytes, and an attachment flag. Reject attachments in 0.1.0. Limit plaintext messages to 1 MiB.

Persist outgoing messages as `queued` before sending, `sent` after authenticated remote receipt, `delivered` after recipient persistence and ratchet advancement, and `failed` for permanent failures. Never retry after identity change or downgrade.

Process incoming data in this order: validate envelope; validate route/session; decrypt/authenticate; validate fragments; bounded reassemble; authenticate/advance ratchet; re-check verified state and pinned generation; atomically persist message and session; acknowledge; expose locally. Any failure must not advance state or expose plaintext.

Every envelope must be exactly 1 KiB, 4 KiB, 16 KiB, or 64 KiB. The visible header contains no plaintext message length, identity key, or peer identity and is authenticated associated data. Encrypted payload contains length, fragment number/count, message ID, and random authenticated padding. Reject all other sizes.

## 9. Transport modes

Direct mode may expose both peer network addresses. Show that warning before confirmation.

Relay mode uses one public relay. It forwards opaque envelopes and cannot decrypt application data. The recipient does not learn the sender's direct address, but the relay sees client addresses and timing.

Privacy mode must use exactly three relay hops:

```text
sender -> entry relay -> middle relay -> recipient relay -> recipient
```

Use nested encrypted relay envelopes. The entry relay knows the sender connection but not the final recipient. The recipient relay knows the recipient connection but not the sender. The middle relay sees only an opaque next hop. Refuse privacy mode when fewer than three relays are configured.

## 10. Cover traffic and batching

Implement exactly these profiles:

```text
standard:      1-second slots, 1 envelope/slot, 4 KiB, 250 ms max batching
low-bandwidth: 5-second slots, 1 envelope/slot, 1 KiB, 500 ms max batching
```

Include the profile in the transcript. Each slot makes exactly one send decision. A real envelope occupies the slot; otherwise send one encrypted cover envelope. Never send real plus cover in one slot. A missed slot is not sent later as a burst. After the idle timeout, stop cover traffic and mark protection paused; resuming requires fresh negotiation. Show bandwidth, battery, and latency cost.

Relays must validate sizes and hop counts before allocation, route by opaque token, enforce connection/route/global quotas, expire routes and queues, reject malformed traffic early, support bounded batching and shuffled forwarding, and never log plaintext, keys, safety numbers, full envelopes, or full addresses.

## 11. Directory, transparency, and recovery

Signed rendezvous responses may distribute public keys, device certificates, relay addresses, and opaque route invitations, but are not trust authority. Include expiry, nonce, service identity, and signature. Reject expired, invalid, duplicate, and lower-generation responses.

Store the last accepted transparency sequence and hash. Accept only the next linked entry or a separately verified checkpoint. Warn and pause affected verification on gaps, rollback, conflicting keys, or unverified certificate replacement.

Recovery requires approval from a verified device, fresh out-of-band verification, or a previously configured independently secured method. Generate a new device key pair, increment certificate generation, sign and atomically persist the certificate, and notify every verified peer. Receiving peers mark the identity `changed`, close sessions, and pause delivery. Never reuse deleted keys or accept a lower generation.

## 12. Required UI wording

Use these exact strings:

`This person's identity has not been verified. Do not send sensitive information until you compare the safety number or scan their verification code through a trusted channel.`

`This contact's security identity changed. Messages are paused until you verify the new identity through a trusted channel.`

`Your messages are end-to-end encrypted. Privacy Mode reduces exposure of message size, timing, and network relationships, but it cannot guarantee anonymity against a global network observer or protect messages on a compromised device.`

Before every session, show mode, peer state, relay count, envelope profile, cover profile, and IP-exposure warning. Require explicit confirmation for direct mode and every mode change. Warnings remain until resolved.

## 13. Required modules and failure handling

Add responsibilities for storage, IPC, transport, rendezvous, relay, session persistence, messages, scheduling, recovery, and audit logging. Suggested modules are `storage.zig`, `ipc.zig`, `transport.zig`, `rendezvous.zig`, `relay.zig`, `session_store.zig`, `messages.zig`, `scheduler.zig`, `recovery.zig`, and `audit.zig`.

Connections have `connect`, `handshake`, `established`, `draining`, and `closed` states with read, write, handshake, and idle timeouts. On shutdown stop new work, finish bounded persisted writes, close connections, clear keys, close IPC, and exit zero. On storage or integrity failure stop processing, close sessions, clear keys, write a safe event, and exit nonzero.

## 14. Tests and implementation order

Test crypto and encoding failures; trust transitions; verification gates; QR mismatch; key-change pauses; recovery generations; encrypted storage; atomic writes; restart persistence; duplicate/reordered/truncated input; quotas; direct/relay/privacy address behavior; three-hop refusal; fixed envelope sizes; cover replacement; missed slots; mode downgrade; relay log hygiene; transparency rollback; and corrupted-session fail-closed behavior.

Run two-core end-to-end tests for initialization, verification, direct messaging, restart, relay messaging, three-relay privacy messaging, cover slots, certificate rotation, re-verification, corruption, downgrade, and every blocked peer state. Add fault injection for drop, duplicate, reorder, truncate, delay, and process interruption. CI must run `zig build test`, `zig build fmt-check`, and the end-to-end suite.

Implement in this order: (1) encoding/storage; (2) identity/device/trust; (3) IPC/CLI; (4) persistent sessions/messages; (5) direct loopback transport; (6) relay transport; (7) privacy routing/scheduler; (8) transparency/recovery; (9) fault tests/quotas/docs; (10) package as 0.1.0.

## 15. Deletion condition

Do not delete this document until all requirements above are implemented, all tests pass, `PROJECT.md` acceptance criteria are checked against actual tests, `README.md` and `docs/protocol.md` describe the shipped behavior, and the release review confirms that no requirement was silently weakened. Then delete `IMPLEMENTATION-0.1.0-CONSTRUCTION.md`, verify `git status` shows it is gone, and keep the permanent implementation documentation only.
