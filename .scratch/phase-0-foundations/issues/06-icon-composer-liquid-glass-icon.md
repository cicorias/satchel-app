# Optional: layered Liquid Glass icon (`.icon`)

Status: needs-triage
Type: task
Blocked by: -

The app currently ships a flat asset-catalog icon (any, dark, and tinted variants). A layered Icon Composer `.icon` would get the full Liquid Glass treatment on iOS 26+.

- The layers are ready in `art/svg/layers/` (background, bag).
- Decide whether this is worth doing before the first TestFlight build. If yes, build `AppIcon.icon` in Icon Composer, reference it from `project.yml`, and document the regeneration steps in `art/README.md`.
