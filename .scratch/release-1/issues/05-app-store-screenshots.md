# App Store screenshots

Status: resolved
Type: task
Blocked by: 01

Fill the three 6.9″ frames in `store/app-store/` (1320×2868, with a dashed 1080 px area for the capture) with real simulator captures:
1. the library with thumbnails;
2. a rendered page;
3. the share sheet with Save page and tags.

Use the iPhone 18 Pro Max simulator, a UI test or script that seeds clean demo items (no personal data), and a compositing step in `scripts/art/`. The rendered PNGs go in `store/app-store/`.

## Answer

`mise run art:screenshots` (`scripts/art/screenshots.sh`) makes `store/app-store/screenshot-{1,2,3}-1320x2868.png`, which are ready to upload.

**Steps:**
1. Erase the simulator. `KEEP=1` skips this.
2. Set light mode and a 9:41 status bar with full bars and battery.
3. Run `StoreScreenshotTests`, which is skipped unless `SATCHEL_SCREENSHOT_DIR` is set through `TEST_RUNNER_…`:
   - **3-library:** the demo library from `-SatchelDemoLibrary` (`DemoLibrary` in `UITestSeed.swift`, Debug only). Six sample items with generated thumbnails, all marked synced, and the sync note hidden.
   - **2-page:** the rendered "Quiet Revolution of Plain Text" page.
   - **1-share:** the share sheet over `site/demo/plain-text.html` (our own sample article) with a note and a tag. It opens from the home screen, so the status bar has no back link.
4. `scripts/art/screenshots.mjs` composites each capture into its frame. The frames now live in `scripts/art/frames.mjs`, shared with `render.mjs`.

**Fixes found along the way:**
- The detail view showed the title twice, in the header and as the body's leading `# title`. The duplicate H1 is now dropped.
- The share sheet's Tags field now dismisses the keyboard on return, and scrolling dismisses it too.
- Frame 2's subline and the site no longer name another app (guideline 2.3.7).

The UI suite passes 11/11, and verify passes 151 Swift tests.
