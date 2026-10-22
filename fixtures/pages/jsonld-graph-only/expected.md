---
id: u_4a9fdd4ebaefde2811b1280012e89373
type: page
title: "Calibrating lidar in the rain"
url: https://journal.northfield-robotics.example/articles/calibrating-lidar-in-the-rain
canonical: https://journal.northfield-robotics.example/articles/calibrating-lidar-in-the-rain
site: "Northfield Robotics"
author: "Amara Velasquez-Thorne, Jun Takeda-Price"
published: 2026-09-30T06:15:00.000Z
saved: 2026-10-22T12:00:00.000Z
updated: 2026-10-22T12:00:00.000Z
description: "Field notes on why wet weather skews our point clouds, and the three-step recalibration routine that fixed it."
image: https://journal.northfield-robotics.example/media/lidar-rain-1600.jpg
tags: []
engine: defuddle@0.19.4 + turndown@7.2.4
---

# Calibrating lidar in the rain

![A test rover in light rain](https://journal.northfield-robotics.example/media/lidar-rain-1600.jpg)

Our outdoor rovers navigate with a spinning lidar on the mast. On dry days it is the most reliable sensor we have. On wet days it starts seeing obstacles that are not there, and the rover stops in the middle of an empty car park and waits for a puddle to move.

We spent most of August working out why. The short answer is that raindrops on the sensor window scatter a little of each outgoing pulse back into the receiver, and the firmware reads that early return as a very close object. The long answer involves a lot of spray bottles and a borrowed garden hose.

## What we changed

1. We now discard returns closer than thirty centimetres unless two consecutive sweeps agree on them.
2. The window has a hydrophobic coating and a small wiper that runs once a minute in wet weather.
3. Each rover recalibrates its range offset against a reference target at the depot every morning.

Since the change, phantom stops in rain have dropped from several per hour to roughly one per shift. We will publish the filter code once it has survived a full winter.
