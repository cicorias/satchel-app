# Artwork

- `src/satchel.mjs` is the **design source**: a leather satchel whose strap is a bookmark ribbon, in the cedar and leather palette. Edit only this file. `bagParts()` splits the bag into body, flap, and ribbon for the layered icon; `bag()` draws them together.
- `svg/` holds the SVG masters, generated from the design source. `svg/layers/` contains the background and the whole bag as separate layers.
- `mise run art` re-renders everything (`scripts/art/render.mjs`, using resvg) into:
  - `apple/Satchel/Resources/AppIcon.icon/`: the **Liquid Glass** app icon (an Icon Composer document, iOS 26+).
    - Its fill is the cedar gradient. Its body, flap, and ribbon layers are separate glass groups, so iOS renders their depth, highlights, and the dark, tinted, and clear appearances itself.
    - It shares the name `AppIcon` with the asset catalog icon, and Xcode uses it in preference.
    - Preview it with `mise run art:icon-preview`, which uses Icon Composer's `ictool` and writes to `apple/build/icon-preview/`.
    - It's generated, so make changes in the design source, not in Icon Composer.
  - `apple/Satchel/Resources/Assets.xcassets/AppIcon.appiconset/`: the flat iOS icon, 1024 px, in any, dark, and tinted variants. Kept as the fallback.
  - `apps/extension/public/icon/`: 16, 32, 48, 96, and 128 px (WXT adds them to the manifest)
  - `store/`: Chrome, Edge, App Store screenshot frames, GitHub social preview
  - `site/assets/`: favicon, touch icon, Open Graph image

Rendered files are committed, so builds don't depend on the art step. Never edit them by hand.
