---
id: u_d54b81a10e6ffdffcaa35c02e945f177
type: page
title: "GitHub - ferncroft/tidepool: A tiny tide-table generator for harbour masters and kayakers."
url: https://github.example/ferncroft/tidepool
canonical: https://github.example/ferncroft/tidepool
site: "GitHub"
author: "ferncroft"
saved: 2026-10-22T12:00:00.000Z
updated: 2026-10-22T12:00:00.000Z
description: "A tiny tide-table generator for harbour masters and kayakers. - ferncroft/tidepool"
image: https://opengraph.githubassets.example/3f1c0a9d2e/ferncroft/tidepool
tags: []
engine: defuddle@0.19.4 + turndown@7.2.4
---

# GitHub - ferncroft/tidepool: A tiny tide-table generator for harbour masters and kayakers.

## tidepool

[![CI](https://github.example/ferncroft/tidepool/actions/workflows/ci.yml/badge.svg)](https://github.example/ferncroft/tidepool/actions/workflows/ci.yml) [![crates](https://camo.githubusercontent.example/9a1f2c/68747470733a2f2f696d672e736869656c64732e6578616d706c65)](https://crates.example/crates/tidepool)

**tidepool** prints tide tables for any harbour with published harmonic constants. It is a single binary with no network access: you give it a station file and a date range, and it gives you high and low water times as a table, CSV, or iCalendar feed.

I wrote it for a sea-kayaking club that was copying times out of a PDF by hand every month. It is small on purpose and will stay that way.

> [!warning] Warning
> Predictions are only as good as the station constants. Do not use tidepool for navigation; check official tide tables before you go out.

## Install

```shell
cargo install tidepool
```

## Usage

```shell
tidepool --station stations/kettle-bay.toml --from 2026-11-01 --days 7 --format csv
```

Or from Rust:

```rust
use tidepool::{Station, predict};

let station = Station::load("stations/kettle-bay.toml")?;
for event in predict(&station, start, days) {
    println!("{} {:?} {:.2} m", event.time, event.kind, event.height);
}
```

A station file looks like this:

```toml
name = "Kettle Bay"
datum = "LAT"
timezone = "Europe/London"

[[constituent]]
name = "M2"
amplitude = 1.82
phase = 214.6
```

## Roadmap

- [x] Table and CSV output
- [x] iCalendar feed
- [ ] Daylight-saving aware output for every station
- [ ] Tidal stream predictions

## License

MIT. See [LICENSE](https://github.example/ferncroft/tidepool/blob/main/LICENSE).
