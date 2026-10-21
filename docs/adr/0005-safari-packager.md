# ADR-0005: Safari via the shared WXT codebase and Apple's packager

- **Status:** Accepted, pending Spike B addendum
- **Amended by:** [ADR-0011](0011-delivery-order-iphone-first.md) (phase order; Spike B stays in Phase 0)
- **Date:** 2026-10-21

**Context.** We want Safari on iOS and macOS from the same code as Chrome and Edge. Apple provides `safari-web-extension-packager` (formerly named `safari-web-extension-converter`), available as `xcrun safari-web-extension-packager` with Xcode and as a web-based tool in App Store Connect.

**What the tool actually does.** Despite the old "converter" name, it does not convert code. It generates an Xcode project containing a host app target (iOS and/or macOS) and a Safari Web Extension target that wraps the existing extension files, plus a stub `SafariWebExtensionHandler` that simply echoes native messages. It reports manifest keys and APIs that Safari does not support. By default the project *references* the original extension files, so rebuilding the web extension updates the Safari extension; `--copy-resources` copies them instead. `--rebuild-project` regenerates an existing project with different options or platforms.

**Assessment: is it clean?**

What is clean:
- The web code is untouched. All extension JavaScript, HTML, and CSS is shared, and Safari reads the same MV3 manifest, ignoring keys it does not support.
- The scaffold is deterministic, and its compatibility warnings are genuinely useful.

What is not clean:
1. **It is a one-shot scaffold, not a build step.** The output is a template project with a placeholder host app, generic UI, and default bundle IDs and team settings. Every customization lives in `project.pbxproj`, which is hard to diff and merge, and re-running with `--force` overwrites those changes.
2. **It assumes it owns the host app.** It generates its own app, but Satchel already has one. We need the extension target embedded in our app, not a second app.
3. **The handler is a stub.** Native messaging logic, the App Group, and CloudKit entitlements must all be added by hand.
4. **Toolchain coupling.** It requires full Xcode on a Mac. WXT builds Safari as MV2 by default, so our build must force MV3.
5. **The App Store Connect web version** targets extension-only apps and doesn't help when the extension ships inside an existing app.

**Verdict:** useful as a reference scaffold; not suitable as the build pipeline.

**Decision.**
1. In Phase 0, run the packager once against the WXT `safari-mv3` output into a scratch directory. Record what it generated (targets, Info.plist keys, entitlements, build settings) in an addendum to this ADR.
2. Recreate those targets in XcodeGen's `project.yml` (ADR-0008) as the `SatchelSafari` target embedded in the `Satchel` host app. Its web resources are a folder reference to the output staged by `build-web.sh`.
3. Re-run the packager only after major Xcode updates, purely to diff Apple's latest template for newly required settings.

**Code sharing.** All extension UI and logic is shared. Safari differences are confined to `apps/extension/src/platform/safari.ts` and the Swift handler:
- Saves go through native messaging instead of CloudKit Web Services (ADR-0007).
- No `identity` API on Safari.
- No `contextMenus` on iOS.
- The background script is non-persistent.
- On iOS, the library lives in the host app.

**Alternatives considered.**
- *A native Safari App Extension in Swift:* the legacy macOS-only model, with no code sharing.
- *Extension.js with `--browser=safari`:* automates the packager and `xcodebuild`, but its Safari support is alpha, it is macOS-only, and it owns the generated Xcode project.
- *Hand-maintaining the generated project:* pbxproj drift and merge conflicts.

## Addendum — 2026-10-21: preliminary Spike B findings

Ran `xcrun safari-web-extension-packager` (Xcode 27.1) against the WXT `safari-mv3` output with `--ios-only --swift`, into a scratch directory. Findings so far:

- **Generated targets:** an iOS host app (UIKit storyboard template with a `WKWebView` onboarding page: `Main.html`, `Style.css`, `Icon.png`) and a `… Extension` app-extension target. Templates' deployment targets ranged from 15.0 to 27.0; `TARGETED_DEVICE_FAMILY = "1,2"`; `SWIFT_VERSION = 5.0`; `GENERATE_INFOPLIST_FILE = YES`; `ENABLE_USER_SCRIPT_SANDBOXING = YES`.
- **Extension Info.plist:** only `NSExtension` → `NSExtensionPointIdentifier = com.apple.Safari.web-extension` and `NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).SafariWebExtensionHandler`. No entitlements are generated (App Group, iCloud, and keychain sharing are ours to add).
- **Handler stub:** echoes `SFExtensionMessageKey` and logs `SFExtensionProfileKey` (iOS 17+). Our handler matches this shape.
- **Resource layout (deviation from Decision item 2):** the packager adds the extension's top-level *files* (`manifest.json`, `background.js`, `popup.html`) individually and its *subdirectories* (`assets/`, `chunks/`, `icon/`) as folder references, so everything lands at the **root of the `.appex`**. A single folder reference to the staged output would nest it one level too deep. `project.yml` therefore copies `apple/Staged/safari-extension/` to the appex root with an `rsync` post-build script (it runs before code signing). This keeps the intent of item 2 (the extension can never drift from the web build), and it picks up new WXT entry points without editing `project.yml`.
- **Settings that differ on purpose:** `ENABLE_USER_SCRIPT_SANDBOXING = NO`, because the web-assets phase writes into `apple/Staged/`; Swift 6 language mode; iPhone only (ADR-0011).

- **Copying the web resources** (superseding the plain `rsync` above): `scripts/build/xcode-copy-safari-resources.sh` copies `apple/Staged/safari-extension/` to the appex root. It first removes whatever it copied on the previous build, using a manifest in the target's DerivedSources, so renamed chunks don't accumulate. A plain `rsync --delete` would also delete the appex's binary and `Info.plist`.

## Addendum — 2026-10-21: Spike B results (the extension runs on iOS)

Verified on the iPhone 18 Pro Max simulator (iOS 27.0, Xcode 27.1) with an **unsigned** simulator build (`CODE_SIGNING_ALLOWED=NO`). Safari accepts it, no Team ID is needed, and the extension appears in Settings.

- **Enabling:** Settings → Apps → Safari → Extensions → Satchel → **Allow Extension**. The extension then appears in Safari's **page menu** (the left button in the bottom tab bar) as "Satchel" with our icon.
- **Popup:** it renders in a sheet with the current tab's title (`browser.tabs.query` works) and the Save buttons. No website-access prompt appeared for `activeTab` use on example.com.
- **Background:** WXT's MV3 `background.service_worker` **works as-is** on iOS Safari, so `background.scripts` + `persistent: false` isn't needed. The worker starts when the extension is enabled and again whenever Safari launches. It's non-persistent, so the background must not assume in-memory state survives.
- **Native messaging:** `browser.runtime.sendNativeMessage` reaches `SafariWebExtensionHandler` from both the popup and the background, with no extra manifest keys beyond `nativeMessaging`. Size and latency results are in the ADR-0007 addendum.
- **Automation:** `mise run test:ios-ui` (`apple/SatchelUITests`) enables the extension in Settings, opens the popup from Safari's page menu, and asserts that it shows the tab title. Quirks the runner handles:
  1. `xcodebuild test` doesn't reliably reinstall the host app of a UI-test target, so the runner does `build-for-testing`, then `simctl install`, then `test-without-building`.
  2. Xcode 27.1 sometimes stalls after the tests finish, while finalizing the result bundle (`operatingSystemBuild … invalidDigitCount`), so the runner stops it once the final suite result has printed.
  3. On a Reader-capable page, the first tap on the page-menu button can toggle Reader instead of opening the menu.
  4. A switch must be tapped on its knob side.
- **Manual steps** for the same flow are in `docs/setup/manual-test-plan.md`.
