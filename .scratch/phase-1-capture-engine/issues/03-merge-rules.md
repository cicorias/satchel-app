# Model: merge rules

Status: ready-for-agent
Type: task
Blocked by: 01

Spec §7.3: earliest `createdAt`, page beats link, union of tags, newest note, metadata never overwritten with an empty value, newer body wins (with a 'replace?' flag for the UI).

**Done when** the merge function is pure and every rule has unit tests, including commutativity where the spec implies it.
