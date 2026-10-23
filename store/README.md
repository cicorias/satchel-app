# Store artwork

Rendered by `mise run art` from `art/src/satchel.mjs`. Don't edit these files by hand.

- `chrome/`: store icon (128 px with padding), small promo tile (440×280), marquee (1400×560)
- `edge/`: logo (300 px), small and large promo tiles
- `app-store/`:
  - `frame-*.png`: 6.9″ iPhone screenshot frames (1320×2868) with headlines, drawn by `scripts/art/frames.mjs`.
  - `screenshot-*.png`: the frames with real simulator captures in them, made by `mise run art:screenshots`. That task erases the simulator, seeds the demo library (`-SatchelDemoLibrary`), sets a clean status bar, runs `StoreScreenshotTests`, and composites the captures. It needs the network, because the share-sheet shot loads `site/demo/plain-text.html`.
  - `listing.md`: the App Store Connect text and App Review notes.
- `github/`: repository social preview (1280×640). Upload it under Settings → General.
