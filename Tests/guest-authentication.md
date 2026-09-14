# Guest / Anonymous empty-password compatibility

- Status: library implementation and regression validation complete: 13 quick tests, memory regression, Moon Player's 33-case network matrix and local-workspace visionOS Simulator Release build passed. Exact App pin and subsequent delivery results are maintained in Moon Player's `docs/smb-guest-authentication.md`.
- Verified: 2026-09-14.
- Source: Moon Player user report of Guest regression in release/1.2.27; request to preserve both authentication paths without reverting memory fixes. No Jira supplied.

`a4e7882` converted every empty password into C NULL. In libsmb2 this suppresses the username and selects Anonymous NTLM, which is not the same as a named Guest session. Keep the old default for source compatibility; expose immutable `SMB2Manager.EmptyPasswordMode.literal` for callers that explicitly want a named user with an empty password. Nonempty passwords are unaffected.

The mode is preserved through manager construction, copy, Codable and NSSecureCoding. Old serialized managers default to `.anonymous`. The existing unsigned Guest Tree Connect handling, callback lifetime guards, read memory ownership, and libsmb2 SHA are unchanged. The library does not silently downgrade explicit account credentials or decide application retry policy.

PR quick: `swift test --filter CallbackLifetimeTests` (13 cases) and `bash Dependencies/libsmb2/tests/test-client-lifecycle.sh`.
The authentication cases cover native NULL versus non-NULL empty passwords, nonempty passwords, the source-compatible default, both modes through copy/JSON/secure archiving, custom port/timeout preservation, and old JSON/secure archives without the new mode key. Existing callback and memory ownership tests remain enabled.
Release: `SMB_FIXTURE_PYTHON=<impacket 0.13.1 Python> bash Scripts/test-read-memory.sh` retains the three-round memory/random-read regression and default anonymous compatibility. Moon Player's `Scripts/test-smb.sh release` adds production-policy network tests for Anonymous-only, Guest-only, both denied, account/blank-password account, wrong credentials and stalled handshakes, with assertions on actual NTLM identities and SMB session flags.

Negative control (2026-09-14): an independent temporary source copy replaced the conditional in `setPassword` with the old `value.isEmpty ? nil : value` conversion. `swift test --filter testLiteralEmptyPasswordIsNotANullSession` built successfully and failed exactly at `XCTAssertNotNil`; the unchanged production checkout passed all 13 tests. This demonstrates that the suite catches this regression rather than merely accepting any successful guest-labelled session. The temporary copy was not a Git worktree and no production source was reverted.
The user subsequently reported that the temporary App build passed their test; server/device details were not supplied. This is supplemental acceptance, not proof of every vendor configuration. Test execution used synthetic loopback credentials only. Remaining compiler warnings include existing Swift weak-variable suggestions and third-party C deprecations/type conversions; none blocked these tests.

The historical Impacket fixture's guest success actually demonstrated Anonymous access; it did not cover a server that permits Guest but rejects Anonymous. Real vendor SMB3/signing/encryption and device playback remain outside these local tests.
