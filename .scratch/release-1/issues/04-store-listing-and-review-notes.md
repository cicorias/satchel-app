# Store listing copy and App Review notes

Status: ready-for-agent
Type: task
Blocked by: 01

Write `store/app-store/listing.md` so it can be pasted into App Store Connect:
- **Text:** name (`apple.appStoreName`), subtitle (30 characters), promotional text, description, keywords (100 characters), what's new.
- **Settings:** category (Productivity), age rating answers, and support, marketing, and privacy URLs (from `config/app.config.json` / `site/`).
- **Privacy questionnaire:** Data Not Collected.
- **Export compliance:** `ITSAppUsesNonExemptEncryption` is already `false`.
- **Review notes:** how to enable the Safari extension (Settings → Apps → Safari → Extensions → Satchel → Allow), and how to share from Safari and from Notes. Note that an iCloud account is needed for sync, but that saves work offline and stay on the device without one.
