# ADR-0018: Work items live in the repo, not GitHub Issues

- **Status:** Accepted
- **Amends:** [ADR-0013](0013-tooling-mise-biome-swift-format.md) (the issue-tracker line)
- **Date:** 2026-10-21

## Context

ADR-0013 recorded GitHub Issues as the tracker for agent work. The developer wants work items to travel with the code: visible in diffs, reviewable in the same commit as the change, readable offline, and usable by agent skills without network access or `gh` authentication.

## Decision

- Work items are Markdown files under `.scratch/<feature-slug>/`, which is **committed**. Each feature directory has a `spec.md` and one file per ticket in `issues/NN-<slug>.md`, with `Status:`, `Type:`, and `Blocked by:` header lines. The conventions are in `docs/agents/issue-tracker.md`.
- Ticket status changes are committed with the work they describe.
- GitHub Issues stay enabled on the public repo for **external** bug reports and support (the site and `LICENSE` point there). They aren't the work queue. When an external report becomes work, it gets a `.scratch/` ticket that links back to it.

## Consequences

- ✅ Work history is in `git log` next to the code. Agents read and update tickets with plain file edits.
- ✅ Tickets are public along with the repo, which matches the source-available stance (ADR-0014). So they must never contain secrets, the Team ID, or account details.
- ⚠️ There's no board UI, assignment, or notifications. That's acceptable for a solo developer; revisit if collaborators join.
- ⚠️ The directory name `.scratch/` is the convention the agent skills expect, even though here it is not scratch space.

## Alternatives considered

- *GitHub Issues (ADR-0013's original choice):* good UI, but the work lives outside the repo and needs network access and `gh` authentication.
- *A `docs/work/` or `TODO.md` file:* doesn't match what the installed agent skills read and write.
