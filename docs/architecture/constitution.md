# Shoko Architecture Constitution

Status: **active law** as of 2026-06-01. Derived from `census-2026-06-01.md`.

## How to use this document

This is the **oracle**. When you are unsure whether a piece of code is "right,"
you do not consult taste — you consult this document. Taste is infinitely
re-litigable and is the reason past refactoring churned. Rules are decidable.

Two consequences:

1. **If a file conforms to every rule here, it is DONE.** You do not revisit it
   because you imagined a nicer shape. "Nicer" is not a defect.
2. **If you think a rule is wrong, you change the *rule* — once, deliberately,
   with a dated reason in the Amendments section — and then bring code into line.**
   You never silently drift individual files away from the rule. This is what keeps
   the constitution itself from becoming a source of churn.

---

## I. Layers (settled — do not re-open)

```
core  →  (nothing)              domain models, domain services, domain events. Pure.
application → core              ports (inbound/outbound), use cases, services, workflows, state.
adapters → application, core    all I/O: UI, input, storage, book sources, output, runtime.
composition → everything        the ONLY place that names concrete classes and wires them.
shared → (nothing app-specific) tiny cross-cutting utilities.
```

**The dependency rule (law):** an inner layer must never reference an outer one.
- `core` references `Adapters::`/`Application::`/`Composition::` **zero** times.
- `application` references `Adapters::`/`Composition::` **zero** times; it talks to
  the outside world only through `Application::Ports`.
- Only `composition` may name concrete adapter classes.

This rule is already satisfied (see census). **There is no further "hexagonal
hardening" work to do.** Do not start any.

---

## II. Decomposition (the rules that stop the churn)

### R1 — Hard zero include-once mixins.
A module that is `include`d or `prepend`ed into **exactly one** class is **forbidden.**
Private behavior belongs as **private methods on its host class**, full stop.

The only way a unit of behavior earns its own file is by becoming a **collaborator
object** — a class you instantiate/inject and *call*, never a module you mix in.

**A collaborator object is justified only if it meets at least one of:**
- it is used by **two or more** call sites, OR
- it owns **distinct state** the host should not hold, OR
- it represents a **distinct domain/role concept** with a name a user of the system
  would recognize, AND it is **unit-tested in isolation**.

If a chunk of a class meets none of these, it stays as private methods. A long,
flat, cohesive class is **correct**, not debt.

**Exempt from R1:** `Application::Ports::*` interface modules (they document a
contract), and genuine shared mixins included by **two or more** classes.

### R2 — Length is never a reason to split.
File/class length does not trigger extraction. Census shows sizes are healthy.
Splitting a cohesive 300-line class into mixins to "shorten" it is an R1 violation.

### R3 — Extract objects, not fragments.
When R1's bar *is* met, the result is a noun-named class with a small public
interface and its own spec — not a `*_support`/`*_actions` grab-bag of the host's
internals.

---

## III. Naming

- **No suffix** `_support`, `_helper`, `_coordinator`, `_dispatch`, `_mixin`,
  `_actions` unless that word is a **real role/domain concept** (e.g. a true
  `Coordinator` pattern with multiple collaborators is fine; `FooSupport` carved
  off `Foo` is not).
- Objects are **nouns** (`FuzzyRanker`, `PageCalculator`). Methods are **verbs**.
- A file is named after the single class/module it defines.

---

## IV. Filesystem shape

- **Max directory depth: 4 levels** under `lib/shoko/<layer>/`. Census found depth 8.
- `require_relative` should not climb more than **2** levels (`../../`). If it climbs
  3+, the file lives in the wrong place — move the file, don't add the `../`.
- **The composition root is allowed to be flat and verbose.** Prefer a few longer,
  boring wiring files over a deep tree of `*_builder`/`*_assembler` directories.
  Wiring is not domain logic; it does not deserve elaborate decomposition.

---

## V. Guardrails = this constitution, executed

- The architecture spec suite exists **only** to enforce the rules above. **One spec
  per rule**, named after the rule.
- Specs named for *moods* — `*_hardening`, `*_coherence`, `*_migration`,
  `final_*`, `no_legacy_*` — are forbidden. They encode a moment, not a law. Delete them.
- To change enforced behavior: amend this doc → update the one matching spec → fix code.
  Never add a spec that pins a one-off decision.

Target shape (~8–10 specs): `layer_dependency`, `no_include_once_mixin`,
`naming_banlist`, `directory_depth`, `rescue_conventions`, `ports_contract`,
`composition_is_only_concrete_wiring`, plus a small number of genuine
domain-invariant specs.

---

## VI. Done

The whole effort is finished when:

> **all consolidated guardrails are green AND a single inside-out pass
> (core → application → adapters) finds zero violations of this document.**

Not "feels clean." The feeling never converges. This checklist does. When it's met,
**stop.**

---

## VII. Explicitly NOT doing (permission to stop)

- ❌ More hexagonal boundary work — boundaries are done.
- ❌ Splitting/merging by file length — sizes are fine.
- ❌ Adding guardrail specs for one-off decisions.
- ❌ Revisiting a file that already conforms.

---

## VIII. Error handling — resilient boundaries (R4)

### R4 — Rescue breadth must match what the guarded code can actually raise.

Two distinct rescue roles. Never conflate them:

1. **Domain-error catches** rescue `Shoko::Error` (or a specific subclass)
   around calls whose *contract* is to raise translated Shoko errors —
   adapters translate raw failures at their edges (`AtomicFileWriter`,
   repositories, importers). Narrow is correct here.
2. **Resilient boundaries** rescue `StandardError`. A resilient boundary is
   any rescue whose begin-block executes code the rescuer does not own:
   subscriber/observer/middleware callbacks, queued background jobs,
   last-resort terminal cleanup, raw stdlib parsing of external input
   (`JSON.parse` of user files), and best-effort warmups. The error set there
   is unbounded — `JSON::ParserError`, `Errno::*`, `ThreadError`, and plain
   bugs are **not** `Shoko::Error`. Writing `rescue Shoko::Error` at such a
   site is a defect: the comment promises containment the class cannot
   deliver.

Every resilient boundary:

- carries a `# resilient-boundary` comment on the line directly above the
  `rescue`. **Enforced:** the marker may only annotate `rescue StandardError`
  (rescue-conventions guardrail).
- routes the error through a named handler
  (`handle_*/record_*/translate_*/swallow_*` + `error`) that logs the error
  class and message, satisfying the existing translation rule.
- does **not** re-raise — isolation means the failure stops here. A
  log-and-rethrow site is not a resilient boundary and must not carry the
  marker.

---

## Amendments

- **2026-06-10 — §V executed: guardrail suite consolidated to 12 rule specs.**
  The 47-file / 4,100-LOC suite is now 12 rule-named files (~2,400 LOC):
  `layer_dependency`, `no_include_once_mixin`, `naming_banlist`,
  `directory_depth`, `rescue_conventions`, `ports_contract`,
  `state_conventions`, `composition_wiring`, `constructor_dependency_budget`,
  `no_reflection_probing`, `boot_surface`, `domain_invariants`.
  - The mood specs (`hexagonal_migration/hardening/coherence`,
    `no_legacy_artifacts`, `zero_fallback_completion`, `command_dispatch`,
    `command_bus`, …) are deleted; their *general* rules moved into the rule
    specs above, their moment-pins and tombstones died with them.
  - `naming_banlist` (§III) and `directory_depth` (§IV) are live as
    **ratchets**: nothing new may take a banned suffix or nest deeper than 4
    levels; the pre-rule holdouts are explicit allowlists that shrink as
    files are renamed/flattened. The §IV require-climb rule (≤2 levels) is
    deferred until the census-P2 flattening of the composition assembler and
    reader TOC trees — the two allowlisted deep prefixes — actually lands.
  - The `*_support.rb` per-directory tracking list (layered_state) is
    superseded by the global `naming_banlist` ratchet.

- **2026-06-10 — R4 (resilient boundaries) added; rescue-narrowing regression fixed.**
  The guardrail consolidation had mechanically narrowed swallowing
  `rescue StandardError` boundaries to `rescue Shoko::Error` to satisfy the
  rescue-conventions spec, leaving inert `# resilient-boundary` comments above
  rescues that no longer contained what the comment promised (stdlib and bug
  errors escaped every isolation point). §VIII now codifies the two rescue
  roles. Converted back to `StandardError` with named handlers: both event
  buses (application + core domain), state-store observer notification,
  background-worker job execution, pagination job submission (now with
  spinner/in-flight rollback on failed submit), config persistence (corrupt
  `config.json` degrades to defaults again), the menu run loop and its three
  terminal-cleanup paths, reader-launch document load and cache validation,
  cached-pagination preload, CLI pagination prebuild, and theme refresh.
  Log-and-rethrow sites lost their misleading markers; dead rescues
  (state-store `dup`, terminal monotonic clock) were deleted. New enforcement:
  the marker may only annotate `rescue StandardError` (rescue_conventions),
  and the hardening-scope example that originally forced markers onto *every*
  broad rescue — the pressure that caused the narrowing — now requires them
  only on swallowing rescues, exempting re-raising translation sites.

- **2026-06-01 — R1 reaches baseline 0; nine documented allowlist exceptions.** Every
  include-once mixin in the codebase has been inlined into its host or promoted to a
  collaborator object, EXCEPT nine files kept as justified exceptions in the ratchet
  scanner's `ALLOWLIST`:
  - `selection_mouse_handler` — bidirectionally coupled to `MouseableReader`'s mouse-state
    machine (shares `@suppress_popup_release_once`/`@selected_text`, ~13 deps). Needs a
    return-based-protocol redesign, not a mechanical extraction.
  - dictionary `setup_flow_support` + `language_pair_support` — the install wizard,
    bidirectionally coupled to `DictionaryController` (calls back into ~8 display/mode
    methods, shares `@setup_session`). Same redesign caveat.
  - the 5 composition-root wiring modules (`infrastructure_registration`,
    `port_and_repository_registration`, `domain_application_registration`,
    `controller_composition`, `controller_composition/menu_builder`) — these are §IV's
    endorsed "few flat wiring files" of the DI graph, included once *by design* to group
    registration/builder wiring. NOT the intra-adapter churn R1 targets.
  - reader_launch `contracts` — typed interface contracts (`PathResolution`, …) that
    implementers include and `ReaderLaunchService` checks via `is_a?` during dependency
    validation. Interface/type markers, the same legitimate role as `application/ports`.
  The ratchet now sits at **0 active violations**; these are tracked, justified, and either
  await deliberate redesigns (selection, dictionary setup) or are accepted §IV/port-style
  organization (composition wiring, contracts).
