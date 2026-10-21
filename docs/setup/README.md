# Human-only setup

An agent can't do these steps, because they need your Apple ID, store accounts, or signing identities. Work through them in this order:

1. [`apple.md`](apple.md): Apple Developer portal identifiers, CloudKit, App Store Connect, and the API key for uploads. **Needed before any device build.**
2. [`github.md`](github.md): repository settings that an agent can't apply from the API.
3. [`browser-stores.md`](browser-stores.md): Chrome Web Store and Edge Add-ons. **Needed in the Chrome/Edge phase.**

All values come from `config/app.config.json`. If a value here disagrees with that file, the file wins, and this doc should be fixed.
