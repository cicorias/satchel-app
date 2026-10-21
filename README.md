<p align="center"><img src="site/assets/icon-512.png" width="128" height="128" alt="Satchel icon"></p>

# Satchel

Save links, and whole pages as clean Markdown, into storage **you** own.

- **Save link:** URL, title, a short blurb, and preview metadata.
- **Save page:** the full article as Obsidian-friendly Markdown with YAML frontmatter, captured from the page you're actually looking at.
- **Your iCloud:** saves go to your private CloudKit database. There are no accounts, no servers, and no tracking.

The app is coming first to **iPhone** (app, Share Extension, and Safari extension), then to **Chrome** and **Edge**. The status is **Phase 0, scaffolding**; see [`docs/spec.md`](docs/spec.md) §14.

## Development

Requirements: macOS with Xcode 27+, and [mise](https://mise.jdx.dev).

```sh
mise run setup      # tools, dependencies, git hooks, generated config
mise run verify     # everything CI checks
mise run run:ios    # build + launch on the iPhone 18 Pro Max simulator
mise run sim:stop   # shut it down again (sim:reset erases it; clean removes builds)
mise run build      # web packages + Chrome/Edge/Safari extension builds
```

To work in Xcode, run `mise run apple:project` and open `apple/Satchel.xcodeproj`. For a device build you first need the Apple portal setup in [`docs/setup/apple.md`](docs/setup/apple.md).

| Where | What |
|---|---|
| [`docs/spec.md`](docs/spec.md) | product and technical specification |
| [`docs/adr/`](docs/adr/README.md) | architecture decision records |
| [`docs/setup/`](docs/setup/) | human-only setup: Apple, CloudKit, stores, GitHub |
| [`AGENTS.md`](AGENTS.md) | layout, commands, conventions (for people and coding agents) |

## License

Source-available, all rights reserved. You may read the code, but you may not redistribute it or publish it to any store. See [`LICENSE`](LICENSE) and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
