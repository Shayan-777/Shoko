# ADR 0003: Review runtime dependencies instead of banning them

Status: accepted — 2026-08-05

An absolute zero-runtime-gem rule rewards local reimplementation even when a
mature library would be safer and cheaper. Runtime gems are allowed after an
explicit review recorded in `../runtime-dependencies.yml`. Shoko currently has
none; that is an outcome, not a target.
