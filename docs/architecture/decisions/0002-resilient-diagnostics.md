# ADR 0002: Diagnostics cannot break containment

Status: accepted — 2026-08-05

Logging at cleanup, observer, background-job, and notification boundaries is
best-effort. A logger failure must not escape the boundary or prevent queue
acknowledgement. The shared resilient diagnostics helper contains logger errors,
and notification completion occurs in `ensure` for every dequeued envelope.
