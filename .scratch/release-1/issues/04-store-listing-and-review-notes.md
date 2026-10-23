# Store listing copy and App Review notes

Status: resolved
Type: task
Blocked by: 01

Write `store/app-store/listing.md` so it can be pasted into App Store Connect:
- **Text:** name (`apple.appStoreName`), subtitle (30 characters), promotional text, description, keywords (100 characters), what's new.
- **Settings:** category (Productivity), age rating answers, and support, marketing, and privacy URLs (from `config/app.config.json` / `site/`).
- **Privacy questionnaire:** Data Not Collected.
- **Export compliance:** `ITSAppUsesNonExemptEncryption` is already `false`.
- **Review notes:** how to enable the Safari extension (Settings → Apps → Safari → Extensions → Satchel → Allow), and how to share from Safari and from Notes. Note that an iCloud account is needed for sync, but that saves work offline and stay on the device without one.

## Answer

`store/app-store/listing.md` has:
- **Text:** subtitle (22 of 30 characters), promotional text (119 of 170), description, keywords (96 of 100, with no other apps' names, per guideline 2.3.7), and what's new.
- **Settings:** category, age rating answers (4+), and URLs.
- **Privacy:** Data Not Collected.
- **Review notes:** share sheet, a share from Notes, the Safari extension steps, iCloud, network use, and export compliance.
