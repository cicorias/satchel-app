---
id: u_7132e305343d9a166fc3ef60c2eca375
type: page
title: "Calibrating the lab printer’s first layer"
url: https://lab.example.net/notes/printer-calibration?view=full
canonical: https://lab.example.net/notes/printer-calibration
site: "Makerspace Lab Notes"
published: 2026-09-02T00:00:00.000Z
saved: 2026-10-22T12:00:00.000Z
updated: 2026-10-22T12:00:00.000Z
description: "A checklist for levelling the bed, setting the Z offset, and tuning first-layer flow on the shared lab printer."
image: https://lab.example.net/static/notes/printer/img/cover.jpg
tags: []
engine: defuddle@0.19.4 + turndown@7.2.4
---

# Calibrating the lab printer’s first layer

Most failed prints on the shared printer fail in the first five minutes, and almost all of those are first-layer problems. This page is the checklist the volunteers use after the bed has been moved, the nozzle swapped, or someone has had a bad afternoon with a scraper.

Jump to [flow tuning](https://lab.example.net/static/notes/printer/#tuning) if the bed is already level, or see the [maintenance schedule](https://lab.example.net/notes/printer-maintenance) for the full service routine.

## 1. Level the bed

Heat the bed to sixty degrees first, because it moves as it warms up. Run the levelling routine from the touchscreen and check the mesh. If any corner is more than three tenths of a millimetre off, adjust the knob under that corner and run it again.

![The bed mesh shown on the printer's touchscreen](https://lab.example.net/static/notes/printer/img/step-1-mesh.jpg)

*A good mesh is mostly green.*

## 2. Set the Z offset

Print the single-layer test square from [first-layer-square.3mf](https://lab.example.net/static/notes/printer/files/first-layer-square.3mf) and adjust the offset while it prints. The lines should be slightly squashed and touch each other without ridges.

![Three test squares: too high, correct, and too low](https://lab.example.net/static/shared/img/z-offset-comparison.jpg)

*Too high, about right, too low.*

## 3. Tune first-layer flow

If the square is right in the middle but rough at the edges, raise first-layer flow by five percent at a time in the slicer profile. Record the final value on the sheet taped to the side of the printer so the next person does not repeat the work.

![The paper record sheet on the printer enclosure](https://lab.example.net/static/notes/printer/img/flow-sheet.png)
