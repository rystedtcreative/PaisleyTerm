# Security Policy

## Reporting a vulnerability

Please report security issues privately to **hello@rcreative.marketing** rather than opening a public issue. You'll get an acknowledgment within a few days. Once a fix ships, the issue will be disclosed in the release notes with credit (if you'd like it).

## Security model

What PaisleyTerm does with your credentials and connections:

- **Passwords live only in the macOS Keychain** (via the Security framework). Connection profiles (`~/Library/Application Support/PaisleyTerm/profiles.json`) store a Keychain reference ID, never the secret. Nothing password-shaped is ever written to UserDefaults, JSON, or logs.
- **SSH key support is not implemented yet.** When it lands, the design constraint already in place is: store key file *paths* only — key material is never copied into app state.
- **Host keys are trust-on-first-use (TOFU).** The first connection to a `host:port` pins the server's public key in `~/Library/Application Support/PaisleyTerm/known_hosts.json`. Every subsequent connection requires an exact match; a mismatch refuses the connection and reports both fingerprints.

## Known limitations

- TOFU means the *first* connection to a host is unauthenticated — a MITM present at first contact could pin its own key. A fingerprint confirmation prompt on first connect is planned; until then, make first connections from a network you trust. To reset a pinned key after a legitimate server change, remove the host's entry from `known_hosts.json`.
- PaisleyTerm's known-hosts store is separate from OpenSSH's `~/.ssh/known_hosts` — keys pinned by `ssh` are not reused.
- Agent status detection parses terminal output; treat status dots as a convenience signal, not a security control.
