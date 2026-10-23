# App Store screenshots

Status: ready-for-agent
Type: task
Blocked by: 01

Fill the three 6.9″ frames in `store/app-store/` (1320×2868, with a dashed 1080 px area for the capture) with real simulator captures:
1. the library with thumbnails;
2. a rendered page;
3. the share sheet with Save page and tags.

Use the iPhone 18 Pro Max simulator, a UI test or script that seeds clean demo items (no personal data), and a compositing step in `scripts/art/`. The rendered PNGs go in `store/app-store/`.
