## Privacy, Metadata Concealment, and Identity Verification

### Security Boundary

RRT provides end-to-end confidentiality, integrity, peer authentication, replay resistance, forward secrecy, and post-compromise recovery when both endpoint devices are uncompromised.

RRT does **not** claim absolute anonymity or protection from a global network observer. A global observer can potentially correlate endpoints through timing, traffic volume, packet size, routing, and long-lived connection patterns. A compromised endpoint can access plaintext while it is displayed or processed.

The system must communicate these limitations plainly in documentation and the user interface.

---

## Metadata-Concealment Mode

RRT must provide an optional `privacy_mode` intended to reduce, but not eliminate, metadata leakage.

### Goals

When `privacy_mode` is enabled, the system should reduce observable differences between active and idle sessions:

- Reduce direct exposure of a peer's IP address to the other peer.
- Reduce leakage of exact message size.
- Reduce leakage of message timing and burst volume.
- Ensure no single relay learns both the sender identity and final recipient identity, assuming at least one relay in the path is honest.
- Avoid using rotating ports as a confidentiality or anonymity mechanism.

### Non-Goals

`privacy_mode` does not guarantee protection against:

- A global passive observer capable of observing all network links.
- A global active adversary capable of selectively delaying, dropping, or correlating traffic.
- Endpoint compromise.
- Users voluntarily revealing their identity through message content or external behavior.

### Relay Topology

The default deployment uses a stable public rendezvous relay. Privacy mode instead uses a multi-hop relay path:
Sender -> Entry Relay -> Middle Relay -> Recipient Relay -> Recipient

Relay responsibilities:

- The **Entry Relay** knows the sender's network address but not the final recipient.
- The **Recipient Relay** knows the recipient's network address but not the sender.
- Middle relays route only encrypted relay envelopes.
- No relay receives end-to-end RRT message keys.
- Relays must not log plaintext, message keys, identity fingerprints, or unencrypted rendezvous metadata.
- Relays should be independently operated whenever practical.

A single participant-hosted relay is acceptable for ordinary encrypted transport, but it cannot provide strong sender/recipient relationship concealment by itself.

### Fixed-Size Envelopes

All RRT traffic in privacy mode must use padded relay envelopes.

Supported envelope classes:
1 KiB
4 KiB
16 KiB
64 KiB

Rules:

1. Application messages are fragmented into one or more fixed-size encrypted envelopes.
2. Short messages are padded before encryption.
3. Padding length is authenticated as part of the encrypted payload.
4. Relay-visible envelopes do not reveal the original plaintext length.
5. Larger messages are sent as multiple independently authenticated fragments.
6. Fragment count still leaks an approximate size range and must be documented as residual metadata leakage.

### Constant-Rate Cover Traffic

Privacy mode must support configurable transmission slots.

Example profile:

slot interval: 1 second
outbound envelopes per slot: 1
idle behavior: send encrypted cover envelope
active behavior: replace cover envelope with real encrypted envelope

Rules:

- A client sends the same number of envelopes per slot whether it has application data or not.
- Real traffic replaces cover traffic; it must not add a visibly larger burst.
- Cover envelopes are encrypted, authenticated, and indistinguishable from normal relay envelopes to relays.
- Clients should maintain the cadence only while a privacy-mode session is active.
- The UI must disclose the bandwidth, battery, and latency cost of cover traffic.
- Users may select a lower-rate profile, but lower-rate profiles provide weaker timing concealment.

### Batching and Delay

Relays in privacy mode should support a bounded batching delay:

minimum batch delay: configurable
maximum batch delay: configurable
default target: low-latency mode

Relay behavior:

1. Accept fixed-size encrypted envelopes.
2. Place them into a short batching queue.
3. Forward envelopes in a shuffled order within the configured delay bound.
4. Emit cover envelopes when required to preserve configured relay output cadence.
5. Rate-limit clients and reject malformed traffic before allocating expensive state.

Batching increases latency and does not defeat a global observer, but it reduces simple one-to-one timing correlation by a local observer or a single relay.

### IP Address Exposure

RRT must distinguish these modes in the UI and protocol negotiation:
direct_mode:
  peers may learn each other's IP addresses.

relay_mode:
  the recipient does not directly learn the sender's IP address;
  the relay operator may still know client network addresses.

privacy_mode:
  traffic is routed through multiple relays;
  no single correctly implemented relay should know both sender and recipient.
  
The selected mode must be included in the authenticated session transcript to prevent silent downgrade from privacy mode to direct mode.

---

## Mandatory Identity Verification

RRT must not permit normal message exchange with an unverified identity.

### Identity States

Every peer identity and device must have exactly one of these states:

pending_verification
verified
changed
revoked
blocked

Only `verified` identities may send or receive application messages.

### Initial Verification

Each user has a long-term identity signing key. Each device has a device certificate binding:
identity public key
device public signing key
device X25519 key-agreement key
device identifier
certificate generation
expiry
Before application messaging begins, users must verify the peer's identity through an authenticated out-of-band method:

- Scan a QR code in person.
- Compare a safety number through an existing trusted voice/video/in-person channel.
- Verify a fingerprint through another independently authenticated channel.

The verification code must be derived from both peers' long-term identity public keys and protocol version.

### Verification Gate

Before verification succeeds:

- The client may establish a limited handshake for identity discovery.
- The client must not display incoming application messages.
- The client must not deliver outgoing application messages.
- The client must not advance the normal message ratchet from unverified application traffic.
- The client must not silently trust a key because it was seen previously.
- The client must display the peer as `Unverified`.

A user cannot bypass verification through a hidden setting or a one-click warning dismissal.

### Key Changes

If a peer's identity key, device certificate, or pinned device key changes:

1. Mark the identity as `changed`.
2. Stop all application-message delivery for that identity.
3. Invalidate the active RRT session.
4. Require new out-of-band verification.
5. Display the old and new safety identifiers.
6. Require an explicit user action before establishing a replacement session.

The application must never silently accept a changed identity key.

### Recovery and Device Replacement

Lost or replaced devices must not silently inherit trust.

A recovery flow must require one of:

- Verification from an already verified device.
- Fresh out-of-band fingerprint verification.
- A previously configured, independently secured recovery method.

A recovery operation must create a new device certificate generation and notify all verified peer devices of the change.

### Identity Transparency

Where a directory or relay service distributes public identity keys, it should provide an append-only, auditable key-transparency log.

Clients should detect and warn about:

- Different identity keys presented to different users.
- Unexpected key rollback.
- Device certificate replacement without a verified recovery event.
- Relay attempts to substitute identity keys.

Key transparency improves detection of key-substitution attacks but does not replace out-of-band initial verification.

---

## Required UI Language

The product must clearly distinguish encryption from anonymity.

Suggested wording:

> Your messages are end-to-end encrypted. Privacy Mode reduces exposure of message size, timing, and network relationships, but it cannot guarantee anonymity against a global network observer or protect messages on a compromised device.

Suggested verification warning:

> This person's identity has not been verified. Do not send sensitive information until you compare the safety number or scan their verification code through a trusted channel.

Suggested key-change warning:

> This contact's security identity changed. Messages are paused until you verify the new identity through a trusted channel.

---

## Acceptance Criteria

### Privacy Mode

- [ ] Direct peer IP disclosure is disabled in privacy mode.
- [ ] Relay-visible packets use only supported fixed-size envelope classes.
- [ ] Idle and active sessions follow the configured send cadence.
- [ ] Real messages replace cover traffic instead of creating observable extra packets.
- [ ] Privacy-mode selection is authenticated in the handshake transcript.
- [ ] A protocol downgrade to direct mode or relay mode is rejected unless the user explicitly starts a new session.
- [ ] The relay cannot decrypt RRT payloads or forge accepted application messages.
- [ ] Documentation states that global traffic analysis remains possible.

### Identity Verification

- [ ] A new identity starts as `pending_verification`.
- [ ] Application messages cannot be sent or displayed before verification.
- [ ] Safety-number and QR verification are supported.
- [ ] Identity or device-key changes immediately pause delivery.
- [ ] Changed keys require explicit re-verification.
- [ ] Device recovery creates a new certificate generation.
- [ ] Old sessions cannot be silently resumed after key rollback or device replacement.
- [ ] Security warnings cannot be silently bypassed.
