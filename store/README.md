# Store artwork

Rendered by `mise run art` from `art/src/satchel.mjs`. Don't edit these files by hand.

- `chrome/`: store icon (128 px with padding), small promo tile (440×280), marquee (1400×560)
- `edge/`: logo (300 px), small and large promo tiles
- `app-store/`:
  - `frame-*.png`: 6.9″ iPhone screenshot frames (1320×2868) with headlines, drawn by `scripts/art/frames.mjs`.
  - `screenshot-*.png`: the frames with real simulator captures in them, made by `mise run art:screenshots`. That task erases the simulator, seeds the demo library (`-SatchelDemoLibrary`), sets a clean status bar, runs `StoreScreenshotTests`, and composites the captures. It needs the network, because the share-sheet shot loads `site/demo/plain-text.html`.
  - `listing.md`: the App Store Connect text and App Review notes.
  - **App preview video:** `mise run art:preview` records the tour on a fresh simulator: welcome, library, saving a page from Safari's share sheet, reading it, and searching. `StorePreviewTests` drives it. `scripts/art/preview-video.swift` (AVFoundation) trims, speeds up, and scales the recording to at most 29.5 s, 886×1920, 30 fps, H.264, with a silent stereo track. The output is `apple/build/preview/app-preview-886x1920.mp4`. It isn't committed (about 18 MB), so re-record it instead.
- `github/`: repository social preview (1280×640). Upload it under Settings → General.
