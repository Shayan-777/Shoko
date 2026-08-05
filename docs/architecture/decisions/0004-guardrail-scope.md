# ADR 0004: Guardrails enforce failure modes, not code shape

Status: accepted — 2026-08-05

Architecture checks now focus on dependency direction, port reality, parseable
sources, state boundaries, composition, constructor clarity, reflection, and
failure containment. Naming bans, directory depth, include cardinality,
duplicate-body similarity, and exact dependency pins were removed because they
produced churn and false confidence. Scanner read/parse failures fail the suite.
