# ios-secure-vault (English summary)

> **A sample / reference code project — NOT a product.** **It has NOT been audited and must NOT hold real secrets.** Use fictional data only.
> Honest limits: [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md). Full documentation is in Portuguese ([README.md](README.md)).

An iOS password / authenticator (TOTP) / API-key vault in **Swift 6 + SwiftUI + Observation**, iOS 17+, with **zero third-party dependencies**.

## What you get
- Three item types (passwords with a configurable generator and strength meter; RFC 6238 TOTP with countdown; API keys/SSH keys/tokens/recovery codes masked until revealed), search, favorites, delete with confirmation.
- Master password + optional Face ID / Touch ID, auto-lock (immediately on background, configurable inactivity), privacy screen, clipboard that expires in 30 s (`localOnly`), growing back-off after wrong passwords, encrypted backup export/import.
- **Crypto:** master password → **PBKDF2-HMAC-SHA256 (600k)** → KEK → unwraps a random **DEK** → **AES-256-GCM** per item (AAD = item id). Everything, including titles, is encrypted at rest (one ciphertext file per item); search happens in memory after unlock. Biometrics unlock a Keychain item (`.biometryCurrentSet`, `ThisDeviceOnly`).
- **Architecture:** a UI-free local Swift package (`VaultCore`: domain, crypto, TOTP, storage) + a thin SwiftUI app; dependency rule `App → VaultCore`; the vault is an `actor`; Swift 6 strict concurrency, warnings as errors; ADRs in `docs/adr`.

## Run it
Needs Xcode 26 and XcodeGen (`brew install xcodegen`).
```bash
make build   make test   make test-ui   make lint   make coverage   make run   make screenshots
```

## Measured (2026-10-06, Xcode 26.6, Swift 6.3.3, iOS 26.5 simulator)
**84 core + 22 app + 6 UI tests green** (UI tests cover create vault, add password, add authenticator, lock/unlock, delete with confirmation, auto-lock on background). VaultCore line coverage **99.5 %** excluding the Keychain file (89.7 % including it); RFC 6238 and PBKDF2 known-answer vectors included. App coverage 76.1 %. `swift-format --strict` clean. Screenshots are real simulator captures (light, dark, XXL text) with fictional data.

## Honest limits
Not audited; PBKDF2 is not memory-hard (Argon2 is not in Apple's frameworks); **Face ID and the Secure Enclave are NOT validated** (the simulator has neither, and the stored DEK is not a Secure Enclave key); Swift strings/keys cannot be wiped from memory; metadata (item count, ids, mtimes) is in the clear; the back-off only slows the UI, not offline attacks; UI tests are not in CI (simulator timing is flaky on hosted runners).
