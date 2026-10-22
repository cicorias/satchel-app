# Share Extension from Safari: page mode, tags, and note

Status: ready-for-agent
Type: task
Blocked by: 06

§9.2.2:
- **Preprocessing script:** add `NSExtensionJavaScriptPreprocessingFile` to `SatchelShare`, which `project.yml` notes as a Phase 3 item. The script wraps `capture.iife.js` and returns `captureLink` and `capturePage` results (FR-4).
- **Sheet:** "Save link" (primary), "Save page" (only when a page capture came back), tags with autocomplete from `Store`, and a note.
- **Memory:** never load images. Pass Markdown as a string, and measure peak memory on the device with a large page, since share extensions have tight limits.
- **Re-saves:** follow FR-6 (link → page upgrades; page → page asks before replacing).

**Done when** sharing from Safari on the iPhone saves both a link and a page (acceptance criterion). A non-Safari share still takes ticket 06's link path. A UI test covers the sheet on the simulator.
