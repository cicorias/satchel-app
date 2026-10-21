# ADR-0012: Minimum iOS 26

- **Status:** Accepted
- **Supersedes:** the minimum-OS line in spec §9.2 (iOS 18 / macOS 15)
- **Date:** 2026-10-21

## Context

Spec §9.2 set iOS 18 and macOS 15 as minimums, "adjust if a required API demands otherwise". The app is new, has no installed base, and the current toolchain is Xcode 27.1 with the iOS 27.1 SDK and Swift 6.4.

## Decision

- Minimum deployment target **iOS 26**; **macOS 26** when the Mac target is enabled (ADR-0011).
- Swift 6 language mode, SwiftUI.

## Consequences

- Liquid Glass is the native design language without availability checks or fallback styling.
- SwiftUI `WebView` / `WebPage` (iOS 26) can render saved Markdown through the shared `packages/render` IIFE and drive hidden-page enrichment (§9.2.4) without `UIViewRepresentable` bridging around `WKWebView`.
- Fewer `#available` branches and a smaller test matrix.
- Users on iOS 18–25 cannot install the app; acceptable for a new product whose first user is the developer.

## Alternatives considered

- *iOS 18 (spec default):* wider reach, but requires `WKWebView` bridging and no Liquid Glass.
- *iOS 27:* newest APIs, but excludes devices still on iOS 26 for no feature we need today.
