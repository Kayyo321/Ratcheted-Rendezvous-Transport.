# Ratcheted Rendezvous Transport (RRT)
## PoC implementation specification

This document is the implementation contract for the proof-of-concept RRT system. An implementation is conforming only if it follows the decisions in this document exactly. Anything not explicitly permitted here is out of scope for the PoC and must not be invented as a compatibility behavior.

The PoC produces two executables:

- `rtt-core`: the local security/session engine and optional relay daemon.
- `rtt-cli`: the human-facing command-line client. It communicates with a local `rtt-core` over a Unix-domain socket and never implements cryptography itself.

The PoC is a research/test implementation. It must never be described as anonymous, metadata-free, production-ready, or safe against compromised endpoints or a global observer.

## 1. Fixed implementation choices

Use these choices without substitution:

| Area | Decision |
|---|---|
| Language | Zig 0.14.1, pinned in CI and documented in `build.zig.zon` |
| Network transport | TCP over IPv4/IPv6; TLS is not used because RRT supplies its own authenticated encryption |
| Local IPC | Unix-domain `SOCK_STREAM` socket, mode `0600` |
| Symmetric encryption | XChaCha20-Poly1305-IETF, 32-byte key, 24-byte nonce, 16-byte tag |
| Key agreement | X25519 |
| Signatures | Ed25519 |
| KDF | HKDF-SHA-256 |
| Hash/fingerprint | SHA-256; display groups are uppercase hexadecimal |
| Randomness | OS CSPRNG only; use `std.crypto.random`/`getrandom` through one adapter |
| Serialization | Canonical CBOR with definite lengths only; no maps in authenticated protocol structures |
| Integer encoding | Unsigned little-endian for fixed-width binary fields; CBOR integers only in CBOR structures |
| Message IDs | 16-byte random values; never counters or timestamps |
| Device IDs | 16-byte random values |
| Session IDs | 16-byte random values |
| Clock | Unix milliseconds, checked with a ±10-minute acceptance window |
| Network framing | 4-byte big-endian length followed by one frame body; maximum body 70,000 bytes |
| Default envelope class | 4 KiB = 4096 bytes total, including all envelope overhead |
| Cover profile | 1 envelope per 1 second |
| Default batching | 25 ms target, 100 ms maximum |

The cryptographic adapter must expose only the operations needed by the protocol. No application module may call a primitive directly. If the selected Zig standard-library API does not provide one of the primitives above, add a pinned, vendored implementation or a pinned C dependency; do not silently replace the primitive.

## 2. Repository layout

Create this layout:

```text
.
├── build.zig
├── build.zig.zon
├── src/
│   ├── core_main.zig
│   ├── cli_main.zig
│   ├── lib.zig
│   ├── crypto.zig
│   ├── encoding.zig
│   ├── errors.zig
│   ├── ids.zig
│   ├── clock.zig
│   ├── identity.zig
│   ├── device.zig
│   ├── trust_store.zig
│   ├── transparency.zig
│   ├── handshake.zig
│   ├── ratchet.zig
│   ├── session.zig
│   ├── envelopes.zig
│   ├── cover_traffic.zig
│   ├── batching.zig
│   ├── relay.zig
│   ├── transport.zig
│   ├── ipc.zig
│   ├── core_commands.zig
│   ├── cli_commands.zig
│   ├── config.zig
│   └── test_vectors.zig
├── tests/
│   ├── crypto_vectors.zig
│   ├── encoding.zig
│   ├── identity.zig
│   ├── handshake.zig
│   ├── ratchet.zig
│   ├── envelopes.zig
│   ├── privacy.zig
│   ├── relay.zig
│   └── cli_e2e.zig
├── docs/
│   └── protocol.md
└── README.md
```

`src/lib.zig` exports reusable modules and tests. `core_main.zig` and `cli_main.zig` are thin entry points. No protocol code belongs in either entry point.

## 3. Build contract

`build.zig` must define these artifacts:

```text
zig build                 # builds both executables
zig build run-core        # starts rtt-core
zig build run-cli         # starts rtt-cli
zig build test            # runs unit and integration tests
zig build fmt-check       # fails if zig fmt would change a source file
```

The artifact names must be exactly `rtt-core` and `rtt-cli`. Build in Debug by default. ReleaseSafe is the only release mode supported by the PoC; ReleaseFast is not a supported security configuration because assertions and safety checks must remain enabled.

CI must run:

```sh
zig fmt --check src tests build.zig
zig build test
zig build -Doptimize=ReleaseSafe
```

The build must fail if the required crypto backend is unavailable. It must not compile a reduced-crypto fallback.

## 4. Process model

### `rtt-core`

`rtt-core` owns all private keys, trust decisions, network sockets, ratchets, relay queues, and persistent state. It runs one local IPC listener and optionally one or more network listeners.

Default paths:

```text
state directory: ~/.rtt
database:        ~/.rtt/state.cbor
private keys:    ~/.rtt/keys/
IPC socket:      ~/.rtt/rtt-core.sock
logs:            stderr only
```

Create directories with mode `0700`, files containing private keys with mode `0600`, and the IPC socket with mode `0600`. Refuse to start if the state directory, key directory, or socket is a symlink. Do not log plaintext, private keys, message bodies, fingerprints, or full network addresses.

The core starts in one of these modes:

```text
rtt-core start                 local client engine; no public relay
rtt-core start --relay         local engine plus relay listener
rtt-core relay                 relay-only process; no identity keys
```

The default relay listener is disabled. Relay-only mode must not create identity keys.

### `rtt-cli`

The CLI connects to the local socket, sends one canonical CBOR command, waits for one response, prints the response, and exits. It must not read or write the state database or private keys directly.

Every command exits with:

```text
0  success
1  user action required (verification, key change, confirmation)
2  invalid command or argument
3  unavailable core or network failure
4  protocol/security failure
5  internal failure
```

## 5. Configuration

The config file is `~/.rtt/config.cbor`. The CLI may create it with `rtt-cli config init`. All values below are mandatory defaults:

```text
privacy_mode       = "relay"       # direct, relay, privacy
envelope_class     = 4096           # 1024, 4096, 16384, 65536
slot_interval_ms   = 1000
envelopes_per_slot = 1
batch_min_ms       = 0
batch_max_ms       = 100
max_message_bytes  = 1048576
relay_listen       = "127.0.0.1:4400"
```

Privacy mode means multi-hop privacy routing. `relay` means a single rendezvous relay. `direct` means peer-to-peer transport. The exact mode is selected per session and is authenticated in the handshake. A configuration change affects only new sessions; existing sessions continue with their negotiated mode until closed.

Reject configurations where:

- `envelopes_per_slot` is zero;
- `batch_min_ms > batch_max_ms`;
- `batch_max_ms > 10_000`;
- `slot_interval_ms < 100`;
- `max_message_bytes` is zero or greater than 64 MiB;
- a privacy session uses fewer than one envelope per slot.

## 6. Identity and device model

### Identity record

At first start, create exactly one local long-term identity:

```text
identity_id:      16 random bytes
identity_signing: Ed25519 private/public key pair
created_at_ms:    uint64
generation:       uint32, initially 1
```

The public identity ID is the SHA-256 hash of the public signing key, truncated to 16 bytes. The private signing key is stored encrypted at rest using a key derived from an interactive passphrase. Use Argon2id with parameters `m=64 MiB, t=3, p=1`, a random 16-byte salt, and XChaCha20-Poly1305 for the encrypted file. The passphrase is never persisted.

### Device certificate

Each local device has:

```text
device_id:              16 random bytes
device_signing_key:    Ed25519 key pair
device_kex_key:        X25519 key pair
certificate_generation: uint32
not_before_ms:          uint64
not_after_ms:           uint64
identity_id:            16 bytes
```

The identity key signs the canonical certificate body. The certificate body is the concatenation of the ASCII domain separator `RRT-DEVICE-CERT-v1` and the fields above in fixed order. A certificate is invalid unless its signature verifies, the identity ID matches the hash of the embedded identity public key, the current time is within the validity interval, and `not_after_ms - not_before_ms <= 366 days`.

### Peer states

Persist exactly one state per peer identity:

```text
pending_verification | verified | changed | revoked | blocked
```

Only `verified` permits application send, receive, decrypt, display, or ratchet advancement. Discovery and verification metadata may be exchanged in `pending_verification`. `blocked` is terminal until an explicit unblocking command. `revoked` cannot be unrevoked; create a new peer record after fresh verification.

## 7. Verification and safety number

The safety number is derived exactly as follows:

```text
left  = min(local_identity_public_key, peer_identity_public_key)
right = max(local_identity_public_key, peer_identity_public_key)
input = "RRT-SAFETY-v1" || protocol_version_u16_le || left || right
digest = SHA-256(input)
display = eight groups of five decimal digits derived from digest
```

Generate each decimal group from five successive digest bytes interpreted as a big-endian integer modulo 100000, zero-padded to five digits. Display the 40 digits grouped as `00000 00000 00000 00000 00000 00000 00000 00000`.

Supported verification methods are exactly:

```text
rtt-cli verify show PEER
rtt-cli verify compare PEER SAFETY_NUMBER
rtt-cli verify qr PEER
```

`compare` succeeds only if the supplied normalized 40 digits equal the locally computed value. `qr` encodes the same safety number plus both identity IDs and protocol version; scanning is an external UI concern for the PoC, so the CLI must print a deterministic `otpauth`-style payload and accept it through `verify qr-import`. No one-click “trust anyway” command exists.

On successful verification, store both identity keys, the verified safety number, verification time, and the exact device certificate set. If any identity key, certificate generation, device signing key, or pinned device X25519 key differs later, transition to `changed`, close the session, delete ratchet state, and require a new verification command.

## 8. Key transparency PoC

Implement an append-only local transparency log format and a relay endpoint, but do not claim it is a production transparency system.

Each log entry contains:

```text
sequence:       uint64, strictly increasing
identity_id:    16 bytes
identity_pub:   32 bytes
device_digest:  32 bytes
previous_hash:  32 bytes
timestamp_ms:   uint64
operator_sig:   Ed25519 signature
```

The entry hash is `SHA-256("RRT-TRANSPARENCY-v1" || canonical_entry_without_signature)`. The operator signs the entry hash. A client rejects gaps, duplicate sequence numbers, bad previous hashes, bad operator signatures, rollback to an earlier sequence, or a key that conflicts with a locally verified key. Transparency warnings never authorize a message; they force `changed` or `blocked`.

## 9. Handshake

The handshake is a Noise-inspired, RRT-specific protocol. Do not substitute an unauthenticated TLS handshake or a custom unauthenticated key exchange.

The initiator sends `HELLO`:

```text
magic                 = "RRT1" (4 bytes)
protocol_version      = 1 (u16)
session_id            = 16 bytes
initiator_identity_id = 16 bytes
initiator_device_id   = 16 bytes
initiator_identity_pub= 32 bytes
initiator_device_cert = canonical certificate bytes
initiator_ephemeral   = 32-byte X25519 public key
requested_mode        = u8 (0 direct, 1 relay, 2 privacy)
requested_class       = u32 (1024, 4096, 16384, 65536)
nonce                  = 32 random bytes
signature              = Ed25519 over all preceding fields plus "RRT-HELLO-v1"
```

The responder sends `WELCOME` with the same fields for the responder, its ephemeral key, selected mode, selected class, and its signature over the complete `HELLO` bytes followed by the complete `WELCOME` fields and `RRT-WELCOME-v1`.

The responder must select the exact requested privacy mode. It may reject the handshake; it may not silently choose a less private mode. A user starting a new session may explicitly request a different mode. The selected mode, envelope class, protocol version, both identity keys, both device certificates, both ephemeral keys, and both nonces are included in the transcript hash:

```text
transcript_hash = SHA-256("RRT-TRANSCRIPT-v1" || HELLO || WELCOME)
```

Both sides verify identity and device signatures, certificate validity, peer state, mode equality, class equality, and freshness before deriving session keys. A peer in any state other than `verified` may finish identity discovery but receives no application payload.

Derive the initial root key with:

```text
dh1 = X25519(initiator_ephemeral_secret, responder_ephemeral_public)
dh2 = X25519(initiator_device_kex_secret, responder_ephemeral_public)
dh3 = X25519(initiator_ephemeral_secret, responder_device_kex_public)
ikm = dh1 || dh2 || dh3
root_key = HKDF-SHA256("RRT-ROOT-v1" || transcript_hash, ikm, 32)
```

Reject all-zero X25519 outputs. The responder uses the equivalent three DH computations.

## 10. Double-ratchet session

Each session has a root key, sending chain, receiving chain, local ratchet key pair, remote ratchet public key, counters, and a bounded skipped-key cache.

Use:

```text
root_step = HKDF-SHA256("RRT-RK-v1", root_key || dh_output, 64)
chain_step = HMAC-SHA256(chain_key, "RRT-CK-v1" || 0x01)
message_key = HMAC-SHA256(chain_key, "RRT-MK-v1" || 0x02)
```

The first 32 bytes of `root_step` become the new root key and the second 32 bytes become the new chain key. A sending message consumes exactly one chain step. A received message with a higher message number derives and stores skipped message keys up to 200 entries; anything beyond that is rejected as `ERR_SKIPPED_KEY_LIMIT`.

Every 50 application messages, and whenever a peer ratchet public key changes, send a ratchet header containing the new ratchet public key and perform a DH ratchet before decrypting the message. A session is invalid if counters decrease, a ratchet key repeats with a conflicting chain, or a message key is reused. Delete consumed message keys immediately.

A session close deletes all live chain keys, root keys, skipped keys, ephemeral secrets, and plaintext buffers. Persistent state may retain only the peer identity, session ID, selected mode, and last monotonic message metadata needed to reject replay; it must never retain recoverable message keys.

## 11. Application message format

An application payload is canonical CBOR with this exact positional array:

```text
[1, message_id_16, sender_identity_id_16, sent_at_ms_u64, utf8_text]
```

Only UTF-8 text is supported in the PoC. Maximum plaintext is `max_message_bytes`. The receiver validates array length, version, fixed byte lengths, timestamp window, UTF-8 validity, sender identity, and message ID replay status before displaying it.

The encrypted message body is:

```text
XChaCha20Poly1305(message_key, random_nonce_24, aad, plaintext)
```

AAD is `"RRT-MESSAGE-v1" || session_id || transcript_hash || ratchet_header || message_number_u32_le`.

## 12. Fixed-size privacy envelopes

Supported total envelope sizes are exactly 1024, 4096, 16384, and 65536 bytes. The selected size is authenticated during the handshake and cannot change during a session.

The envelope is a fixed-size byte array:

```text
offset  size  field
0       4     magic = "RTE1"
4       1     version = 1
5       1     envelope_type (cover=0, data=1, ack=2, relay=3)
6       1     hop_count
7       1     flags; currently zero
8       16    route_id
24      16    envelope_id
40      8     sequence
48      24    nonce
72      N     ciphertext plus authentication tag
rest          random padding to the selected class size
```

The entire area from offset 40 through the end is encrypted/authenticated by the intended next hop. The visible header is only routing metadata and must not contain identity IDs, IP addresses, plaintext length, message type beyond the required envelope type, or timestamps. The authenticated plaintext begins with:

```text
[payload_version=1, payload_kind, fragment_id_16, fragment_index_u32,
 fragment_count_u32, actual_payload_len_u32, payload_bytes]
```

`actual_payload_len` is inside the ciphertext. Padding is random and included in the authenticated plaintext length calculation. A fragment is independently authenticated. The sender fragments the encrypted application message into chunks that fit the class; the receiver reassembles only after every fragment verifies and all indexes are present. Maximum fragment count is 4096.

Cover payloads use the same structure with `payload_kind=cover`, zero payload length, random fragment identifiers, and random authenticated padding. Real data replaces a scheduled cover envelope; it never adds a second envelope in the same slot.

## 13. Traffic slots and batching

For an active privacy session, define slot `n` as `session_start_monotonic + n * slot_interval_ms`. At each slot, the client must enqueue exactly `envelopes_per_slot` envelopes. If no real data is queued, enqueue cover envelopes. If more real data is queued than the slot budget, queue the remainder for later slots. Never send a burst to catch up after a delay.

The sender may be late by up to one slot interval; it must not disclose the amount of lateness in the wire format. A closed or suspended session sends no cover traffic.

The relay batches per route and class. It waits at least `batch_min_ms` when possible, never longer than `batch_max_ms`, then shuffles queued envelopes with a CSPRNG and forwards them. It must enforce per-client queue limits before allocating expensive cryptographic state:

```text
max active routes per connection: 64
max queued envelopes per route:   256
max envelope body:                65536
max malformed frames per minute:  20
```

When a queue is full, reject new traffic with a generic rate-limit result. Never reveal whether a destination exists.

## 14. Relay topology and routing

Direct mode: the two endpoints establish TCP directly. The peer may learn the source address; the UI must say so.

Relay mode: both peers connect to one rendezvous relay. The relay forwards opaque end-to-end envelopes. The recipient does not receive the sender's source address from protocol data, but the relay can observe both client addresses. The UI must say so.

Privacy mode: the sender creates three nested relay layers for `entry -> middle -> recipient`. Each relay sees only the previous and next transport connection and an opaque fixed-size envelope. The entry relay sees the sender connection but not the final recipient. The recipient relay sees the recipient connection but not the sender. The route is built from three distinct relay IDs; reject a privacy route with fewer than three hops or duplicate relay IDs.

Each layer is encrypted to the relay's published X25519 public key. Relay public keys are pinned in the route descriptor and authenticated by the endpoint handshake. Relays never receive end-to-end message keys. Route descriptors contain relay IDs and public keys only; they never contain plaintext recipient identity data.

The PoC relay API is a framed TCP protocol with `REGISTER`, `OPEN_ROUTE`, `ENVELOPE`, `CLOSE_ROUTE`, and `ERROR` frames. Relay authentication is by an operator-signed relay certificate. A relay that cannot validate a route certificate must reject the route before queue allocation.

## 15. Replay and abuse controls

Maintain a bounded replay cache per peer and per session:

```text
maximum message IDs: 100000
maximum envelope IDs: 100000
eviction: oldest insertion order
```

Replayed valid ciphertext is rejected without user-visible plaintext. Replayed malformed traffic counts toward the malformed-frame limit. Never answer differently for “unknown recipient”, “bad route”, and “bad envelope” in a way that allows enumeration; use the generic error `ERR_REJECTED` on the network.

## 16. Local IPC protocol

The local socket uses the same 4-byte big-endian length framing, with a maximum body of 1 MiB. Request and response bodies are canonical CBOR positional arrays.

Request envelope:

```text
[1, request_id_16, command_utf8, args_array]
```

Response envelope:

```text
[1, request_id_16, status_u8, result_or_error]
```

Commands are exactly:

```text
identity.show
identity.export
peer.add
peer.list
peer.show
verify.show
verify.compare
verify.qr
verify.qr-import
session.start
session.close
message.send
message.list
config.show
config.set
relay.status
shutdown
```

The core must validate the request ID, command name, argument count, argument types, and authorization state. CLI arguments are converted to the CBOR request; the core remains the sole authority.

## 17. CLI contract

Implement exactly these commands:

```text
rtt-cli identity show
rtt-cli identity export --public
rtt-cli peer add IDENTITY_ID
rtt-cli peer list
rtt-cli peer show IDENTITY_ID
rtt-cli verify show IDENTITY_ID
rtt-cli verify compare IDENTITY_ID SAFETY_NUMBER
rtt-cli verify qr IDENTITY_ID
rtt-cli verify qr-import IDENTITY_ID PAYLOAD
rtt-cli session start IDENTITY_ID [--mode direct|relay|privacy]
rtt-cli session close SESSION_ID
rtt-cli message send IDENTITY_ID TEXT
rtt-cli message list IDENTITY_ID
rtt-cli config show
rtt-cli config set KEY VALUE
rtt-cli relay status
rtt-cli shutdown
```

Human-readable output is the default. `--json` emits one JSON object per command, with stable keys and no secrets. `message send` must refuse with exit code 1 when the peer is not `verified`, when identity state is `changed`, or when no session exists. It must print the exact reason and the required verification command.

The startup banner and `privacy_mode` output must include this text or a semantically identical fixed string:

```text
Messages are end-to-end encrypted. Privacy Mode reduces exposure of message size,
timing, and network relationships, but it cannot guarantee anonymity against a global
network observer or protect messages on a compromised device.
```

For unverified peers, print:

```text
This person's identity has not been verified. Do not send sensitive information until
you compare the safety number or scan their verification code through a trusted channel.
```

For changed peers, print:

```text
This contact's security identity changed. Messages are paused until you verify the new
identity through a trusted channel.
```

## 18. Persistent state

Persist one canonical CBOR state document with a schema version. Writes are atomic:

1. write `state.cbor.tmp` with mode `0600`;
2. flush and fsync the file;
3. rename over `state.cbor`;
4. fsync the parent directory.

Never partially update the live state. On startup, recover a valid `.tmp` only if the primary state is absent; otherwise delete the stale temporary file.

Persist identities, peer states, certificates, config, transparency checkpoints, route descriptors, and replay metadata. Do not persist plaintext messages, message keys, root keys, chain keys, ephemeral keys, or cover payloads. `message list` therefore lists only messages received during the current core process unless an explicitly encrypted message archive is implemented later; the PoC must return an empty list after restart rather than inventing persistence.

## 19. Error model

Define stable error codes in `errors.zig`:

```text
ERR_INVALID_ARGUMENT
ERR_NOT_FOUND
ERR_UNVERIFIED
ERR_IDENTITY_CHANGED
ERR_REVOKED
ERR_BLOCKED
ERR_BAD_CERTIFICATE
ERR_BAD_SIGNATURE
ERR_BAD_TRANSCRIPT
ERR_MODE_DOWNGRADE
ERR_UNSUPPORTED_CLASS
ERR_BAD_ENVELOPE
ERR_REPLAY
ERR_SKIPPED_KEY_LIMIT
ERR_RATE_LIMIT
ERR_CORE_UNAVAILABLE
ERR_STATE_CORRUPT
ERR_CRYPTO_FAILURE
ERR_REJECTED
```

Security-sensitive network failures must be collapsed to `ERR_REJECTED`. Local CLI errors may be specific. Error text must never include keys, plaintext, full packets, or secret-derived material.

## 20. Testing requirements

Tests are mandatory before declaring the PoC complete.

### Deterministic tests

Use fixed test vectors for every primitive adapter, safety number, certificate, transcript hash, HKDF step, envelope padding, and fragment reassembly. The vectors must include expected hex output and be independent of wall clock or OS randomness.

### Identity tests

Test invalid signatures, expired certificates, wrong identity IDs, generation rollback, all five peer states, changed-key detection, revoked peers, and refusal to message before verification.

### Handshake tests

Test successful direct, relay, and privacy handshakes; mismatched modes; requested privacy downgraded by responder; wrong certificate; wrong transcript; stale timestamps; all-zero X25519; duplicate session IDs; and relay paths with fewer than three distinct hops.

### Ratchet tests

Test in-order delivery, out-of-order delivery, skipped-key recovery, skipped-key limit, duplicate message rejection, ratchet-key change, counter rollback, session close key deletion, and post-compromise recovery after a DH ratchet.

### Privacy tests

Use a fake clock and fake network recorder. Assert:

1. active and idle sessions emit the same envelope count per slot;
2. a real message replaces a cover envelope instead of adding one;
3. visible envelope lengths are only 1024, 4096, 16384, or 65536;
4. plaintext length is absent from visible bytes;
5. mode is present in and protected by the transcript;
6. direct/relay downgrade is rejected;
7. privacy routes always have three distinct relay IDs;
8. the relay cannot decrypt end-to-end payloads;
9. fragment count is bounded and documented as residual leakage;
10. batching never exceeds its configured maximum delay.

### Integration tests

Launch two `rtt-core` processes and one, then three, fake relays. Use `rtt-cli` to add peers, compare safety numbers, verify them, establish each mode, send messages, stop/restart a core, rotate a device certificate, and confirm the expected pause. Capture exit codes and stdout/stderr. No test may assert anonymity; tests assert only the specified observable properties.

### Fuzz tests

Fuzz canonical CBOR decoding, network frame parsing, certificate parsing, envelope parsing, relay routing, and IPC requests. Every malformed input must return an error without panic, unbounded allocation, or state mutation.

## 21. Observability and logging

Log only structured events to stderr:

```text
startup, shutdown, handshake_result, session_open, session_close,
verification_changed, relay_rate_limit, malformed_frame, state_recovery,
transparency_warning
```

Each event may include a short session ID prefix and error code. Never log IP addresses, ports, identity IDs, device IDs, fingerprints, message IDs, route IDs, plaintext, keys, ciphertext, or exact packet sizes. A debug flag may increase event counts but cannot disable these redactions.

## 22. Documentation and acceptance checklist

`README.md` must explain build prerequisites, commands, state paths, relay setup, verification workflow, the three modes, cover-traffic cost, and all security limitations from `PROJECT.md`.

The implementation is accepted only when all of the following are true:

- both named executables build with `zig build`;
- all private-key operations occur in `rtt-core`;
- no application message is sent or displayed for an unverified peer;
- identity, certificate, and pinned-device changes force `changed` and pause messaging;
- direct mode exposes peer addresses and says so;
- relay mode hides the sender address from the recipient but not from the relay;
- privacy mode uses three distinct relays, fixed-size envelopes, and authenticated mode selection;
- active and idle privacy sessions use the same configured slot cadence;
- real traffic replaces cover traffic;
- relay-visible packets contain no end-to-end keys or plaintext;
- unsupported envelope sizes are rejected;
- downgrade attempts are rejected;
- state and keys have the required filesystem permissions;
- malformed input cannot crash the core or allocate without bounds;
- the required warning language is visible in the CLI;
- tests cover every requirement in the testing section.

No feature may be marked complete because a UI warning exists. The corresponding protocol enforcement, state transition, test, and CLI behavior must all exist.
