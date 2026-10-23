# Optional: layered Liquid Glass icon (`.icon`)

Status: resolved
Type: task
Blocked by: -

The app currently ships a flat asset-catalog icon (any, dark, and tinted variants). A layered Icon Composer `.icon` would get the full Liquid Glass treatment on iOS 26+.

- The layers are ready in `art/svg/layers/` (background, bag).
- Decide whether this is worth doing before the first TestFlight build. If yes, build `AppIcon.icon` in Icon Composer, reference it from `project.yml`, and document the regeneration steps in `art/README.md`.

## Comments

2026-10-23: the user kept the flat icon for release 1. A layered `.icon` is still optional for a later release.

2026-10-23: the user asked for the layered icon on its own branch (`feat/liquid-glass-icon`), with a PR to main.

## Answer

`mise run art` now also generates `apple/Satchel/Resources/AppIcon.icon` from the design source, with no hand work in Icon Composer:
- **Fill:** the cedar gradient (`linear-gradient`, top to bottom).
- **Groups, front to back:** `ribbon` (opaque, so its green holds), `flap`, and `body` (translucency 0.2). All three are glass, with neutral shadows. The SVGs come from `bagParts()` in `art/src/satchel.mjs`. `bag()` draws the same parts, so every other rendered asset is unchanged; the PNGs are byte-identical.
- **Xcode:** XcodeGen 2.46 adds the document as `wrapper.icon` in the app's Resources. It shares the name `AppIcon` with the asset catalog icon, and Xcode uses it in preference. The built `Assets.car` holds the icon image stack, groups, and vector layers. The flat `AppIcon.appiconset` stays as the fallback.
- **Checked:** `mise run art:icon-preview` (`ictool`) renders the default, dark, and tinted appearances correctly, and the iOS 27 simulator's home screen shows the glass icon.
