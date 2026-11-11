# Changelog

## 0.3.8 — 2026-11-11

- Fix sync stopping before sending when Forever reports an outgoing restriction
  flag even though the normal addon-message API works. Sending now uses the
  actual API result, retaining throttling, bounded retries and lockdown errors.
- Default the optional heartbeat to 15 minutes for missing or invalid settings.
  Existing choices, including Off, are preserved.
- Add `/bm selftest`, a manual 15-second solo diagnostic for local profile
  decoding, actual send results, and guild/self-whisper echoes. It tests both
  full-name formats and sends at most three tiny hidden test messages.
  `/bm selftest report` repeats the locally saved result.
- Expand `/bm debug` with the actual send result, advisory restriction flag and
  own-echo count. Self echoes are never counted as another member's snapshot.

Validation: 391 automated checks, four startup scenarios and Lua 5.1 syntax
checks passed. Live testing confirmed complete outgoing transfers and their
self echoes. Delivery between different accounts remains unverified.

Guildmates should install this version and reload before testing shared data.
