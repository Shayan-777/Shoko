# ADR 0001: Bound every import pipeline

Status: accepted — 2026-08-05

Imported formats can amplify small inputs through compression, recursion,
dimensions, and parser structure. All importers therefore share an import budget
for source bytes, expanded bytes, resources, structural units, nesting, and
dimensions. Format parsers may tighten these limits. Exceeding a limit rejects
the import rather than truncating it.
