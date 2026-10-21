# Artwork

- `src/satchel.mjs` is the **design source**: a leather satchel whose strap is a bookmark ribbon, in the cedar and leather palette. Edit only this file.
- `svg/` holds the SVG masters, generated from the design source. `svg/layers/` contains the background and bag as separate layers, ready to import into **Icon Composer** (Xcode → Open Developer Tool) if you want a layered Liquid Glass `.icon` later.
- `mise run art` re-renders everything (`scripts/art/render.mjs`, using resvg) into:
  - `apple/Satchel/Resources/Assets.xcassets/AppIcon.appiconset/`: iOS icon, 1024 px, in any, dark, and tinted variants
  - `apps/extension/public/icon/`: 16, 32, 48, 96, and 128 px (WXT adds them to the manifest)
  - `store/`: Chrome, Edge, App Store screenshot frames, GitHub social preview
  - `site/assets/`: favicon, touch icon, Open Graph image

Rendered files are committed, so builds don't depend on the art step. Never edit them by hand.
