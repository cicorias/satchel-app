# Manual test plan

These checks aren't automated yet, or need a real device. Use them before a TestFlight build and after Safari or iOS updates. The automated version of 1–2 is `mise run test:ios-ui`.

## 1. Enable the Safari extension (iPhone)

1. Install the app (`mise run run:ios` on a simulator, or a signed device build).
2. Open **Settings → Apps → Safari → Extensions → Satchel**, and turn on **Allow Extension**.
3. Expected: Satchel's icon and the description from `config/app.config.json` are shown, and the switch stays on.

## 2. Open the popup

1. In Safari, open any article page (e.g. https://example.com).
2. Tap the **page menu** button (left side of the bottom tab bar). If the page switches into Reader mode instead, tap it again.
3. Tap **Satchel**.
4. Expected: a sheet with the Satchel header, the page title, **Save link** and **Save page** buttons, and a status line.

## 3. Native messaging (device)

On a device, repeat the Spike D measurement (ADR-0007 addendum). It needs temporary probe code; see `.scratch/phase-0-foundations/issues/08-verify-native-messaging-on-device.md`.

## Later phases

Share Extension saves, offline queueing, and cross-device sync checks get added here in Phase 3 (spec §14).
