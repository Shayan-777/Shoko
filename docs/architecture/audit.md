# Shoko Architecture Audit

A living reference for the architectural state of `lib/`. This is the yardstick
and the ledger — not a one-time report.

## How to use this document

- Future sessions **update checkboxes** as findings are fixed, **add new
  findings** when discovered, and **never delete a finding**. When something is
  resolved, check its box and append a one-line `Resolved (YYYY-MM-DD):` note
  pointing at where the code now proves it. If a finding turns out to be wrong,
  ~~strike it through~~ with a note rather than removing it.
- A checked box means *verified by reading the current code*, not "we remember
  fixing it." Cite the file/region that proves it.
- Findings have stable IDs (`ARCH-n`). Reuse them in commits and notes. IDs are
  never recycled.
- Severity = **architectural blast radius** (how much is downstream), not line
  count or fix cost.

## Audit provenance

- Date: 2026-05-31. Method: blind read of the `lib/` tree plus the 56 guardrail
  specs in `spec/core/architecture/` and their support files
  (`spec/support/architecture/`).
- **Ruby pinned to 3.4.9 (2026-05-31).** The repo previously pinned Ruby 4.0.1
  while the dev machine ran 3.4.9. `.ruby-version`, the gemspec
  `required_ruby_version`, and the two CI workflows were aligned to 3.4.9, and
  the dev/test bundle re-materialized for the 3.4 ABI. The app is stdlib-only at
  runtime (zero third-party runtime gems), so it boots unchanged; only the
  dev/test gems were reinstalled.
- **The guardrail suite now runs green here.** Pre-change baseline on 3.4.9:
  **211 architecture examples, 0 failures, 42 pending** (the 42 pending are the
  `*_support.rb` DEFERRED directories — see ARCH-3). Claims marked "verified by a
  green run" below were confirmed by executing the relevant specs, not just
  reading them.

---

## Target architecture (the aspiration)

Hexagonal / ports-and-adapters, dependencies pointing inward, with an explicit
layer matrix enforced by `spec/support/architecture/layer_policy.rb`:

| Layer | May depend on |
|---|---|
| `core` | core, shared |
| `application` | application, core, shared |
| `adapters` | adapters, core, shared — **plus** `application/ports/` (any) and `application/use_cases/requests/` (input adapters only) |
| `composition` | everything (the single composition root) |
| `shared` | shared only (pure-utility leaf) |

Decisions this codebase has **deliberately** made (they are not accidents, and
the guardrails encode them):

- **Ports are owned by `application/`**, split `inbound/` (driving) and
  `outbound/` (driven). `core/ports/` is *forbidden* to exist
  (`adapter_boundary_spec`). `application/ports/` is importable from **every**
  layer, including core (`layer_dependency_spec:59`).
- **One state store** (`application/state/state_store.rb`): immutable snapshot,
  copy-on-write, schema-partitioned, event-driven, thread-safe. It is the single
  in-memory source of truth and is application infrastructure, not an adapter.
- **Fail-fast, no fallbacks**: no synthetic error documents, no proc-type
  fallbacks, no implicit null runtime config, no reflection (`send`/
  `public_send`/`respond_to?`) in core/application/runtime/composition.
- **Error-handling is a typed discipline**: broad `rescue StandardError` is
  banned except in an allowlist of two files, each requiring a
  `# resilient-boundary` marker; a rescue must *name* its handling
  (`raise` / `raise_x` / `return x_error` / `handle_|record_|translate_|swallow_*error`).
  `FatalExternalInputError` is the sanctioned external-input boundary type.
- **Container access is quarantined** to composition roots; everything else
  receives typed collaborators by constructor injection.

---

## Layering map — intended vs. actual (2026-05-31)

| Layer | Intended | Actual (verified) |
|---|---|---|
| `core/` (43 files) | Pure domain: models, services, events, errors | **Pure**, except one sanctioned edge (ARCH-1). `core/models/` has **0** outward refs. Only one `require` leaves the whole tree. |
| `application/` (231 files) | Orchestration, ports, state, use-cases, workflows, services | **No adapter references** (0). I/O-free (enforced, zero exemptions). Owns ports + state store. Holds UI view-state (ARCH-2). |
| `adapters/` (560 files, 64k LOC) | All I/O, UI, parsing, storage | **Boundary-clean**: talk to application only via `application/ports/` and `use_cases/requests/` DTOs. UI touches **0** sibling adapters. Format/parse complexity correctly quarantined here. |
| `composition/` (49 files) | The one wiring root | Proper phased composition root; container resolution/mutation confined to it. |
| `shared/` (25 files) | Pure-utility leaf | Pure except 4 audited `File`/`IO` uses (bundled unicode tables, gem probing, path hashing). No outward refs. |

**Macro verdict:** the hexagon holds. Dependency direction is essentially
pristine — the *only* wrong-way edge in 92k lines is ARCH-1, and even that is
explicitly exempted by the layer policy. This is a genuinely well-built
hexagonal codebase, and its single largest architectural asset is that the
architecture is *executable*: 56 guardrail specs make the boundaries regression-proof.

---

## Established & enforced — verified clean (do not "fix")

These are checked because the current code upholds them. They are the
"don't touch" list; treat a future regression here as a real defect.

- [x] **Dependency direction inward.** `application`→`adapters`: 0 constant
  refs, 0 requires. `core`→`adapters`/`composition`: 0. `shared`→outward: 0.
  UI→sibling-adapters: 0. *Verified by reading + exhaustive grep of constant
  refs and require edges; enforced by `layer_dependency_spec`,
  `adapter_boundary_spec`, `strict_hexagonal_wiring_spec`.*
- [x] **Ports are real contracts**, not ceremony. Inbound (3) implemented by
  use-cases (`reader_intent_handler.rb`, `menu_intent_handler.rb`); outbound (93)
  are method-bearing modules with `NotImplementedError` defaults. *Verified by
  reading `ports/{inbound,outbound}/*` samples and their implementers.*
- [x] **State store is sound**: immutable snapshot + copy-on-write structural
  sharing, `SchemaRegistry` fragments, event emission, `Mutex`. *Verified by
  reading `application/state/state_store.rb`.*
- [x] **Error/rescue discipline** (the "translation" convention with named
  handlers). *Verified by reading `rescue_guardrail_analyzer.rb`; broad-rescue
  allowlist is 2 files.*
- [x] **No reflection / no fallbacks** in the strict scope. *Verified by reading
  `hexagonal_migration_guardrails_spec`; spot-grep found 0 `send`/`public_send`
  in core/application.*
- [x] **Application is I/O-pure**: `EXEMPT_APPLICATION_FILES` is empty.
  Spot-grep for `File.`/`IO.`/`puts`/`$stdout` in core+application returned 0.
- [x] **Prior relocations stayed put**: `StateStore`/`ObserverStateStore`/
  `EventBus` live in `application/state` (not `adapters/runtime/session_state`);
  `Core::Models::Session`, `Shared::MenuDefinitions` gone; `DisplayLine` absent
  from core. *Enforced by `layered_state_guardrails_spec` 1–2 & 5.*
- [x] **Application renders through outbound ports**, not callbacks/controller
  redraws (no `force_redraw`/`render_callback` in application). *Enforced by
  `hexagonal_migration_guardrails_spec`.*

---

## Root causes & findings

### ROOT R1 — "Application-as-boundary-owner"

The codebase centralizes *boundary artifacts* in `application/`: the ports
(consumed even by core) **and** the state store (holding even UI view-state).
This is internally consistent and deliberate — it gives one composition
authority and one state authority — but it is the common root of the two
deepest tensions below (ARCH-1 and ARCH-2). The "correct shape" for both is a
single decision: **either embrace this stance and document it as the intended
architecture** (then these stop being "violations" and become the design), **or
reject it and push boundary artifacts to where they are logically owned**
(domain-owned driven ports; UI-owned view-state). Everything else is a symptom
or a tail.

---

- [x] **ARCH-1 — Core depends on an application-owned port.** Severity: **Medium**
  (tiny footprint, foundational stance).
  - **Resolved (2026-05-31)** — verified by reading + a green run. The coupling
    existed *solely* to power a defensive `is_a?` contract check. The check and
    the port `require` were removed from `core/services/in_book_search_service.rb`;
    the core now trusts its typed collaborator, and a non-conforming object fails
    fast on first use — matching the codebase's own no-probing philosophy. (A
    first attempt using `respond_to?` duck-typing tripped that very no-reflection
    guardrail — `hexagonal_migration_guardrails:165` — which is *why* removing the
    check outright, rather than re-implementing the probe, is the correct fix.)
    Locked permanently by two new guardrails in `adapter_boundary_spec`: *forbids
    application constants in core sources* and *forbids core sources from
    requiring application files* (the latter closes the global `application/ports/`
    require exemption for the core specifically). Verified: core now has 0
    `Application::` refs and 0 `application/` requires; architecture suite 213/0/42;
    core+search 286/0. This settles **Q2 for the core specifically** — the domain
    depends on nothing outward, not even ports — while ports remain
    application-owned and adapter-importable.
  - Where (original): `core/services/in_book_search_service.rb` — a `require` of
    the application port plus an `is_a?` check against
    `Shoko::Application::Ports::Outbound::DynamicPageSource`. Implemented by
    `application/services/pagination/page_calculator_service.rb:30`.
  - Why it mattered: the domain's compile-time graph reached *up* into
    `application/` — the one place physical package layering and logical
    dependency layering disagreed. Sanctioned by the policy, so not a rule-break,
    but the cost of R1 leaking into the core.

- [x] **ARCH-2 — The application state store owns UI presentation/view state.**
  Severity was **High** as an open design question; **Low** as a correctness risk.
  - **Resolved by decision (2026-05-31): ratified Option A.** The single
    application-owned, schema-partitioned store is the *intended* architecture
    (the "single store" pattern), not a temporary compromise. UI-presentation
    state lives in the view/UI-designated fragments of that store (`ReaderView`,
    `UiGlobals`, and the view-shaped fields of `MenuProcess`), written by the UI
    and observed through outbound ports. There is **no Option-B (per-layer UI
    store) migration planned.** Dropped the "compromise / future-work / Option B"
    framing from the three schema docstrings and the `layered_state_guardrails_spec`
    comments/messages; the §3 denials now read as the **permanent partition rule**
    (UI-shape fields only in the designated view/UI fragments). Docs/wording only —
    no behaviour change, suite stays green.
  - What's preserved: the fence — `layered_state_guardrails_spec` §3 still denies
    UI-shape fields in `ReaderProcess`/`ReaderPagination`/`MenuTransient`/`Config`/
    `Core::Reading::Schema`. That discipline is now permanent, not transitional.
  - Optional future tidy-up (not a boundary change, not required): consolidate the
    presentation-shaped fields currently in `MenuProcess` into a dedicated
    menu-view fragment of the *same* store, mirroring `ReaderView`.
  - Where (original): `schema/reader_view.rb`, `schema/ui_globals.rb`,
    `schema/menu_process.rb` hosted UI-presentation state with docstrings that
    framed it as a compromise awaiting an Option-B migration.

### ROOT R2 — Unfinished, fenced refactor tails

Migrations the codebase started, fenced against regression, but has not
finished. These are **cohesion/consistency** debt, **not** boundary violations —
low blast radius, but real and (in one case) wide.

- [ ] **ARCH-3 — `*_support.rb` mixin pattern: pervasive and officially
  deprecated.** Severity: **Low** blast radius, **high** footprint. **In progress.**
  - **Progress (2026-05-31):** 105 → **83** files (22 single-includer mixins
    folded back into their hosts and deleted); **11 directories** promoted to
    `LIVE_DIRECTORIES` (book_sources fb2/epub/kindle importers + xhtml parser;
    output line_assembler / table_renderer / kitty_image_renderer; pagination
    page_calculator / page_info / coordinator; cli folder_import_workflow). Full
    suite green (1505/0/36). Method: 3 manual folds proved the pattern, then a
    validated codemod (`/tmp/fold_support.rb`, not committed) for the rest — it
    only touches all-private single-includer modules, computes the indent shift
    from each module's nesting, and inserts before the *correct* class end in
    multi-class files (all three were real bugs the suite caught). Stable,
    non-UI / non-input dirs were done first to avoid colliding with in-flight work.
  - Remaining (83): the public-API / own-require `*_support` the codemod skips
    (need manual placement — rss, buffer `frame_render`, pagination_orchestrator,
    menu_builder); the `adapters/ui/**` + `adapters/input/**` dirs (deferred —
    conflict risk with the in-flight Option-A inversion); and the 12 shared mixins
    + 6 standalone `*_support` modules (need collaborator-extraction / rename, not
    a fold).
  - Where: **105** `*_support.rb` files (43 in `adapters/ui`, 18 in
    `adapters/input`, 10 in `adapters/output`, rest scattered). Only **1**
    directory (`application/services/reader/bookmark_service`) is cleaned and
    enforced; `layered_state_guardrails_spec` lists **~40** `DEFERRED_DIRECTORIES`.
  - Why it matters: the pattern extracts helpers into a mixin solely to keep a
    host file under a line budget, fragmenting one responsibility across files
    and creating implicit coupling (the mixin assumes host ivars). It does *not*
    cross a layer boundary, hence Low severity — but it is the largest tail by
    file count.
  - Correct shape: fold each mixin back into its host (or extract a real
    collaborator object with an explicit interface), directory by directory, and
    promote each from `DEFERRED_DIRECTORIES` to `LIVE_DIRECTORIES`.

- [x] **ARCH-4 — Snapshot port duplication (composite vs. focused).** Severity:
  **Low**.
  - **Resolved (2026-05-31)** — verified by reading. Investigation reclassified
    the finding: this is *not* transitional duplication. The composites are the
    deliberate **cross-slice read model** — `MenuSessionAccess#current_menu`
    builds `MenuSnapshot` by merging the session + transient stores (and
    `update_menu` splits writes back via `MenuStatePartition.split`); the reader
    projection adapter builds `ReaderSnapshot` by merging the session + view +
    pagination stores. Forcing those consumers onto focused snapshots would be a
    regression in ergonomics (juggling 2–4 objects per read). So took the audit's
    other branch: corrected the misleading "preserved / prefer focused" docstrings
    on both ports to state the design plainly — composite for cross-slice reads,
    focused for single-slice. Comment-only; 39 snapshot/port examples green, suite
    unaffected (comments are stripped by guardrails).
  - Where (original): composite `MenuSnapshot`/`ReaderSnapshot` docstrings implied
    they were legacy shims to migrate away from.

### ROOT R3 — Guardrail-net blind spots

The 56-spec net is excellent but has a few holes; a hole is a *meta* risk
(future regressions slip through, or a green spec gives false assurance).
Severity: **Medium-Low** (affects regression safety, not current correctness).

- [x] **ARCH-5 — Stale/vacuous guardrail assertion.**
  - **Resolved (2026-05-31)** — verified by reading + a green run. Chose
    *repoint* over *delete*: deletion would have lost unique protection, since no
    other guardrail catches this method-call-level coupling (`command_dispatch`
    bans legacy *type* names; `adapter_boundary` catches *constant* refs, not the
    `context.ui_controller` call). Repointed the assertion from the phantom
    commands glob to the whole `application/**` layer — it now scans 230 real
    files (was 0), and the reader/menu action use-cases do receive a routing
    `context`, so it's a live tripwire. Verified `context.ui_controller`/
    `context.state_controller` = 0 across application; layer_dependency_spec green.
  - Where (original): `layer_dependency_spec` asserted the pattern only within a
    `commands/` use-case directory that no longer exists (0 files) → vacuous. The
    removed path is independently fenced by `command_dispatch_guardrails`
    (verified 2026-05-31: it fired on this audit doc when the legacy token was
    quoted), so only the `layer_dependency` copy needed fixing.

- [x] **ARCH-6 — No orphan/test-only-port guardrail; one such port exists.**
  - **Resolved (2026-05-31)** — verified by reading + a green run. A one-off
    classifier over all 96 ports (83 interface, 12 value-type, 1 catalog)
    confirmed `ReaderChapter` was the *only* orphan — every other interface port
    has a production `include`r. The "make `Core::Models::Chapter` satisfy the
    port" option was rejected: the port is consumed by *core* services, so having
    a core model name an application port would recreate the exact
    `Application::`-in-core coupling just removed in ARCH-1. So: **deleted
    `reader_chapter.rb`** and dropped the `include` from the 3 spec doubles (they
    already define their own `title`/`lines`, so they duck-type cleanly — same as
    production).
  - **Guardrail added** (`spec/core/architecture/no_orphan_ports_spec.rb`): every
    interface port (one declaring `NotImplementedError` stubs) must have ≥1
    production `include`r. Scoped to interface ports so value-type/catalog ports
    aren't false-flagged; checks the *implementer* side only — consumers
    legitimately duck-type, so a consumer-side check would be unreliable. Proven
    non-vacuous: it flagged `ReaderChapter` red before deletion, green after. The
    "implemented-but-unconsumed" case stays undetectable (duck-typing-opaque) and
    is explicitly out of scope — noted in the spec, not solved.
  - Verified: architecture suite 214/0/42; the 3 de-coupled specs green; 0
    `ReaderChapter` references remain anywhere.
  - Where (original): `application/ports/outbound/reader_chapter.rb` — `include`d
    only by 3 spec doubles, no production implementer or consumer.

### Lower-severity / trivia (note, don't prioritize)

- [x] **ARCH-7 — `Time.now` bypasses the time port.** Severity: **Trivial.**
  - **Resolved (2026-05-31)** — verified by reading + a green run. Investigation
    changed the fix: the stamped `timestamp` was written in exactly one place
    (`emit_event`) and **read nowhere** (subscribers use only `event.type`/`.data`),
    so injecting a `WallClock` port would have added a dependency just to populate
    dead data. Instead **removed the dead `timestamp` field** from the application
    `State::Event` struct — eliminating both the dead data and the `Time.now`
    bypass in one move, with zero spec churn (constructor unchanged). If event
    timestamps become a real requirement, add them deliberately via the injected
    `WallClock` port, as the core `DomainEventBus`/`EventFactory` already do.
    Core+application are now `Time.now`/`Date.today`-free; suite 214/0/42; 75
    blast-radius examples green.
  - Where (original): `application/state/event_bus.rb` stamped events with
    `Time.now` — the only port-bypass found in the application layer.
- [ ] **ARCH-8 — Direct `ENV[...]` reads in two terminal adapters.** Severity:
  **Trivial / judgment.** `adapters/output/terminal/terminal.rb:175`
  (`SHOKO_COLOR_MODE`) and `adapters/output/kitty/kitty_graphics.rb:93`. A
  terminal adapter reading terminal-detection env is defensible; a purist would
  route even these through `env_runtime_config_adapter`. Decide and be
  consistent.

---

## Judgment calls / open questions (decisions to make, not bugs)

These are genuine grey areas where reasonable architects disagree. Track them as
decisions, not defects.

- **Q1 — Where does UI view-state belong? — DECIDED 2026-05-31: Option A.**
  Single central store holding view-state (Redux/Elm style) is a legitimate,
  widely-used pattern and gives one observable source of truth; the hex-purist
  position is that presentation state is UI-adapter-owned. The project ratified
  **Option A** — the single application-owned store is the intended design; UI
  state lives in its view/UI fragments, written by the UI and observed through
  outbound ports. The "compromise / Option B migration" framing was removed from
  the schema docstrings and the guardrail spec. See ARCH-2 (now resolved).

- **Q2 — Where do driven ports the *domain* needs belong?** (drives ARCH-1 and
  R1.) "Application owns all ports, importable everywhere" is coherent and keeps
  one port package; classic hexagonal/DDD says the domain owns the driven ports
  it depends on. **Decision needed:** either bless application-owned-neutral
  ports as the rule (then ARCH-1 is not a violation), or carve a core-owned
  ports package for the handful of ports the domain consumes.

- **Q3 — Is 93 outbound ports interface segregation or proliferation?** The
  repository/store/capability/infra ports (`Clock`, `DocumentLoader`,
  `DictionaryRepository`, …) are clearly real. The narrow `menu_*`/`reader_*`
  *control* ports (e.g. `MenuBrowseInspection`, `MenuModeSwitcher`) are the
  proliferation risk — they may be one-implementer/one-caller seams. ISP argues
  for narrow; pragmatism argues some could be consolidated. **Leaning:**
  acceptable; revisit only if maintenance friction shows up. Not a defect.

- **Q4 — Are the reader/menu controllers god-objects?** No, by file size — the
  largest controller file is 243 lines and the reader controller is decomposed
  into many <250-line focused classes. The breadth shows only as ~25 grouped
  `*Dependencies` parameter-object structs (capped 8–10 by
  `constructor_dependency_budget_spec`). This is *managed* decomposition of an
  inherently broad TUI, not a monolith. **Leaning:** acceptable; the budget
  specs are the right guard. Not a defect.

---

## Severity-ranked summary (roots at top, symptoms beneath)

1. **ROOT R1 — Application-as-boundary-owner** (the stance behind ARCH-1 + ARCH-2)
   - **ARCH-2** — ✅ *resolved 2026-05-31 by decision* — ratified Option A (single store is the intended design); Q1 decided
   - **ARCH-1** — ✅ *resolved 2026-05-31* — Core→application port edge (Medium); Q2 settled for the core
2. **ROOT R3 — Guardrail blind spots** (Medium-Low)
   - **ARCH-5** — ✅ *resolved 2026-05-31* — vacuous assertion repointed to the whole `application/**` layer (live tripwire)
   - **ARCH-6** — ✅ *resolved 2026-05-31* — dead `ReaderChapter` port deleted; orphan-port guardrail added (`no_orphan_ports_spec`)
3. **ROOT R2 — Unfinished fenced tails** (Low blast radius)
   - **ARCH-3** — `*_support.rb` mixin tail (105 files, 1/~40 dirs cleaned) — wide footprint
   - **ARCH-4** — ✅ *resolved 2026-05-31* — reclassified as a legitimate cross-slice read model; misleading docstrings corrected
4. **Trivia**
   - **ARCH-7** — ✅ *resolved 2026-05-31* — removed the dead `timestamp` field (the `Time.now` bypass); core+app now `Time.now`-free
   - **ARCH-8** — `ENV[...]` in two terminal adapters

Open questions (not ranked, decide deliberately): **Q1**–**Q4**.
