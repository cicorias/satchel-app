# ADR-0008: XcodeGen for the Apple project

- **Status:** Accepted
- **Date:** 2026-10-21

**Decision.** Define all Apple targets in `apple/project.yml` and generate `Satchel.xcodeproj` locally and in CI. The generated project is not committed.

**Reasons.**
- Readable diffs and no `project.pbxproj` merge conflicts.
- Agent-friendly: YAML target definitions are reliable to edit, whereas hand-editing pbxproj is error-prone.
- Makes it easy to reproduce the packager's settings (ADR-0005) explicitly.

**Alternatives considered.**
- *A committed `.xcodeproj`:* merge pain and opaque diffs.
- *Tuist:* more powerful but more to learn. Reconsider if the project grows substantially.
