# Constitution history

The original architecture constitution grew from a short layer policy into a
994-line combined policy, audit log, exception list, and amendment journal. Its
useful conclusions remain in the active constitution; this file records the
evolution without making old migration mechanics permanent law.

## 2026-06: architecture census

The census found that dependency direction was healthy, while single-host mixin
shredding, deep composition paths, and overlapping guardrails caused most of the
maintenance friction. See `../census-2026-06-01.md` for the measured baseline.

## 2026-07: hardening amendments

The project added nominal port checks, constructor/dependency ratchets, strict
rescue conventions, state-access rules, reflection bans, and composition checks.
These caught real regressions, but exact-count pins and increasingly elaborate
source scanners also encoded historical implementation shapes as policy.

## 2026-08: policy reset

The active constitution was rewritten as concise present-tense policy. The
guardrail suite dropped naming, directory-depth, include-count, duplicate-body,
and exact dependency-count proxies. Remaining scanners fail closed. Durable new
decisions are recorded as ADRs instead of amendments to the policy document.

The full pre-reset text remains available in version-control history immediately
before this rewrite.
