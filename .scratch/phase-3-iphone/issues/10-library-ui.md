# Library: search, filters, detail view, export, delete

Status: ready-for-agent
Type: task
Blocked by: 06

FR-7 and §9.2.4 "Library UI":
- **List and search:** search with FTS5 from ticket 04, filters by tag and kind, newest first.
- **Detail view:** renders the Markdown with `render.iife.js` in a `WKWebView`. Remote images follow the setting from ticket 12. No navigation inside the web view: links open in Safari.
- **Actions:** copy Markdown, export `.md` through the share sheet (link Items export frontmatter plus the description, §5), delete, and open the original URL.
- **Pending state:** show it (FR-8).

**Done when** UI tests on the simulator cover search, opening the detail view, export, and delete. The detail view is verified to run no page scripts and to load no remote content while remote images are off.
