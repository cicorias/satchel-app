---
id: u_8c72952ba176703ef1fa116049d2deac
type: page
title: "Configuring workers — Quarry 3.2 documentation"
url: https://quarry.readthedocs.example/en/stable/guide/workers.html#scaling
canonical: https://quarry.readthedocs.example/en/stable/guide/workers.html
site: "quarry.readthedocs.example"
saved: 2026-10-22T12:00:00.000Z
updated: 2026-10-22T12:00:00.000Z
description: "A Quarry worker is a long-running process that pulls tasks from a broker and runs them. This page covers how many tasks a worker runs at once, how to run more workers when the queue grows, and how to stop them without losing work."
tags: []
engine: defuddle@0.19.4 + turndown@7.2.4
---

# Configuring workers — Quarry 3.2 documentation

A Quarry worker is a long-running process that pulls tasks from a broker and runs them. This page covers how many tasks a worker runs at once, how to run more workers when the queue grows, and how to stop them without losing work.

> [!note] Note
> Settings on this page can be given on the command line, in `quarry.toml`, or as environment variables prefixed with `QUARRY_`. The command line wins when the same setting appears in more than one place.

## Concurrency

By default a worker runs one task per CPU core. Tasks that spend most of their time waiting on the network can safely run at a much higher concurrency.

```console
$ quarry worker --concurrency 32
```

The same setting in a configuration file:

```toml
[worker]
concurrency = 32
prefetch = 4
```

## Scaling

Workers share nothing but the broker, so you can add more of them on any machine that can reach it. Quarry does not scale workers for you; use your process manager or orchestrator and watch the `queue_depth` metric.

> [!warning] Warning
> Raising `prefetch` above the default can starve other workers of tasks, because each worker reserves that many tasks before it starts any of them.

## Graceful shutdown

On `SIGTERM`, a worker stops taking new tasks and waits up to `shutdown_timeout` seconds for running ones to finish. Tasks still running after the timeout are returned to the queue.

> [!tip] Tip
> Set the timeout a little longer than your slowest task, not your average one.
