# Shoko Architecture Constitution

Status: **active law** as of 2026-06-01. Derived from `census-2026-06-01.md`.

## How to use this document

This is the **oracle for architectural shape**. When you are unsure whether a
piece of code is structured "right," you do not consult taste — you consult
this document. Taste is infinitely re-litigable and is the reason past
refactoring churned. Rules are decidable.

Scope, stated plainly: conformance here means *architecturally done relative
to the current rules*. It is not a claim of correctness, security, or
completeness — green guardrails have coexisted with reproducible correctness
holes, and no rule set replaces tests, code review, or adversarial audit.

Two consequences:

1. **If a file conforms to every rule here, it is architecturally DONE.** You
   do not revisit its *shape* because you imagined a nicer one. "Nicer" is not
   a defect. (Its *behavior* remains as reviewable as any code.)
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
A module that is `include`d, `prepend`ed, or `extend`ed into **exactly one** host
is **forbidden.** `extend` is the same fragmentation through the singleton class,
not a loophole. Private behavior belongs as **private methods on its host**, full
stop. (`extend self` — the module-function idiom — is not a mixin site.)

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
contract); genuine shared mixins included by **two or more** classes; the
composition-root wiring modules and interface-contract modules enumerated —
each with its rationale — in the scanner `ALLOWLIST`
(`spec/support/architecture/include_once_mixin_scanner.rb`). The rule and its
executable enforcement name the same exemptions; an ALLOWLIST addition is a
constitutional amendment.

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

- **2026-07-12 — §IV executed on the reader composition tree; the engine
  binary leaves the repo.**
  - **The 16-file reader builder/assembler tree collapsed into two flat wiring
    files.** `controller_composition/reader_builder/**` (8 files:
    `assembly`, `resolved_dependencies`, `runtime_preparation`,
    `runtime_context_builder`, `dependency_set`, `controller_factory`,
    `controller_dependency_factory`) and
    `controller_composition/reader_runtime_assembler/**` (8 files, incl. the
    `controller_builder/{state_builder,ui_graph_builder}` sub-tree) were each a
    pass-through stage — no external call site, no isolated spec — handing a
    `Data` bundle to the next stage. This is §IV's named anti-pattern ("a deep
    tree of `*_builder`/`*_assembler` directories" for wiring that "does not
    deserve elaborate decomposition"). They are merged into
    `reader_builder.rb` (container resolution → runtime preparation → staged
    dependency groups → controller instantiation) and
    `reader_runtime_assembler.rb` (anchor resolver, pagination, controllers,
    render coordinator, observers). Both are `module_function` wiring modules
    of `build_*` methods, exactly §IV's "few longer, boring wiring files."
    `controller_composition.rb` lost its `instance_method(...).bind_call(self,
    ...)` reflection dance — a straight `ReaderBuilder.build_controller(...)`
    delegation replaces it — and the dead, never-called
    `build_reader_runtime_components` seam is gone. The composition-wiring,
    boot-surface, and ports-contract guardrails now point at the two files
    instead of the deleted directories; the stale
    `controller_dependency_factory.rb` MethodLength todo entry moved to
    `reader_builder.rb` (one 12-kwarg `ReaderIntentHandler.new` wiring call,
    §IV-endorsed).
  - **The compiled `shoko-translate` engine binary is no longer tracked.** A
    60 KB host-specific ELF executable was committed under
    `ext/shoko_translate/`; it is a build artifact of the checked-in C sources,
    platform-locked, and re-generated by `make`. It is now git-ignored, and the
    CI `ruby` workflow gains a `translate-engine` job that compiles the engine
    from source, smoke-tests its JSON protocol (`{"op":"ping"}`), and fails if
    any non-source file reappears under `ext/` — so the C code stays
    build-verified without a binary in history.
  - **§III executed on the XHTML parser: four constants, four files.**
    `xhtml_content_parser.rb` defined four sibling top-level classes
    (`XHTMLContentParser` + `XHTMLContentTraversal`, `XHTMLBlockBuilder`,
    `XHTMLSegmentBuilder`), violating §III's "a file is named after the single
    class it defines." Each collaborator now lives in its own file
    (`xhtml_content_traversal.rb`, `xhtml_block_builder.rb`,
    `xhtml_segment_builder.rb`); the facade keeps only `XHTMLContentParser` and
    requires the three. The one cross-class coupling —
    `XHTMLContentParser.markup_hidden?`, a static predicate the traversal and
    segment builder both called back into the facade for — became
    `MarkupVisibility.markup_hidden?`, a small `module_function` utility with a
    real role concept, called (not mixed) by its two collaborators, so the
    sub-components no longer depend backward on the facade (R1's ≥2-caller bar,
    not an include-once mixin).

- **2026-07-11 — Class fragments banned (R1's other door); the symbolize sweep
  actually finished; both naming/reflection ratchets closed.**
  - **Reopening a class in a second file to inject methods is now a violation,
    enforced.** Two hosts had their private methods smeared across satellite
    files that reopened the class — `JsonCacheStore` (5 fragment files:
    `payload_helpers`, `chapters`, `layouts`, `resources`, `manifest`) and
    `EpubCache` (`memory_cache`, `persistence`, `source_reference`, plus its
    `Serializer` module split across `serialize`/`deserialize`/`helpers`
    behind a require-stub). This is the include-once mixin without the
    `include` — the same fragment indirection R1/R3 ban, invisible to the
    include scanner (whose own comment noted reopenings are not flagged) and
    in direct violation of §III's one-constant-per-file rule. All fragments
    are merged into their host files (`json_cache_store.rb`, `epub_cache.rb`,
    one `serializer.rb` — R2: length is never a reason to split), and
    `no_include_once_mixin` gains a third example backed by
    `ClassReopeningScanner`: no class or module may receive direct method
    definitions from two or more files. No allowlist. Files that reopen a
    class purely to define a nested collaborator constant (`WrappingService::
    FetchRequest`, `BookFinder::ScannerContext`, `StateStore::ChangeSet`, …)
    are unaffected — the nested constant owns its defs.
  - **The 2026-07-11 symbolize consolidation is now actually complete.** The
    earlier sweep removed only helpers *named* `symbolize_*`; ~36 sites in 30
    files still re-implemented `HashNormalizer.symbolize_keys` inline or under
    `normalize_*` names, with drift already present (two
    `respond_to?(:to_sym)` variants). Every site now delegates to
    `Shared::HashNormalizer` (`symbolize_keys`/`deep_symbolize`), preserving
    each site's own non-Hash contract (`|| {}`, nil, raise). The related
    `block_type == :image || block_type.to_s == 'image'` dual-typing trilogy
    (dynamic page-map builder, single/split view renderers) now delegates to
    the existing `Core::Models::BlockType.image?`/`canonical` — the canonical
    predicate had existed all along and simply wasn't used.
  - **The naming-banlist ratchet closed: the allowlist is gone.** All twelve
    pre-rule holdouts were renamed to role nouns or folded:
    `OPFElementNameHelpers`→`OPFElementQueries`; `LifecycleHelpers`→
    `ImporterLifecycle`; `StyleSupport`→`StylePrimitives`; `ListHelpers`→
    `ListWindowing`; `ConfigHelpers`→`ConfigResolution`; `ContextHelpers`→
    `SnapshotQueries`; `ProgressHelper.ratio`→`ProgressRatio.compute`; the two
    same-named `session_outcome_helpers.rb` files became
    `SessionOutcomeAccess` (controllers read outcomes) and
    `SessionOutcomeConstruction` (UI sessions build them);
    `dependency_record_mixins.rb` split into `dependency_builder.rb` +
    `dependency_validation.rb` (one module per file, §III); the four-constant
    `annotation_rendering_helpers.rb` split into `annotation_screen_rendering`
    / `annotation_view` / `annotation_text_box` / `annotation_edit_state`,
    losing its `defined?(@ivar)` probes; `payload_helpers.rb` died in the
    fragment merge. `naming_banlist` now enforces the suffix ban with no
    allowlist.
  - **Two stale reflection-allowlist entries removed.** `destination_resolver`
    probed `doc.respond_to?(:chapters)`/`chapter_count` with fallbacks though
    `Ports::Outbound::ReaderDocument` pins `chapters`/`chapter_count`/
    `get_chapter` (this amendment cycle itself had added `chapters` to that
    port) — it now calls the port directly. `reader_view_model_builder` probed
    `source_path`, which the port did *not* declare: the port now pins
    `source_path` (its implementer always exposed it) and the probe is gone.

- **2026-07-11 — Dead test-mode seam deleted; R4 enforced in the inverse direction; the last two width-blind word-wraps consolidated.**
  - **The test-mode terminal seam is gone — it never did what it claimed.**
    `TestSupport::TestMode` promised "deterministic test behaviour by swapping
    in lightweight adapters": its const-swap replaced `Shoko::Terminal`, an
    alias (`lib/shoko/terminal.rb`) that no file named explicitly, and
    `TerminalService` resolves `Terminal` lexically to the real facade anyway,
    so the swapped-in `TestTerminalService` still drove the real terminal. Its
    `queue_input`/`drain_input`/`configure_size` helpers had no callers and
    pushed keys into a queue nothing read. All of it — the alias file,
    `test_mode.rb`, the composition root's `apply_test_configuration` hook,
    and the stale `test_container_registration.rb`/`test_mode.rb`
    composition-wiring allowlist entries — is deleted. The alias's one
    *implicit* consumer surfaced by the deletion — `KittyImageLineRenderer`
    reached the facade through bare-constant lookup (`output: Terminal`) —
    now receives the sink as `RenderDependencies#terminal_output`, wired from
    `terminal_service.output` like every other dependency. `TerminalDouble`
    (the part that was real: specs inject it explicitly) survives, with its
    `ensure_input_queue` bug fixed (it populated `@ensure_input_queue` instead
    of `@input_queue`) and a contract-accurate non-blocking read (`nil` when
    empty, matching `TerminalInput#read_key`, instead of raising
    `ThreadError`).
  - **R4 now also bans the inverse defect: `rescue Shoko::Error` over code
    that cannot raise it.** Seventeen sites guarded pure primitives with dead
    rescue+fallback branches — untested code that either never ran
    (`TextSanitizer.sanitize` and `RenderStyle.color` never raise; the pdf/
    fb2/kindle importers, epub serializer, cached-library repository,
    lifecycle helpers, annotation editor, `sanitize_xml_source`'s
    self-rescue, and the kitty line renderer's `String#split` guard all lost
    theirs, as did the page-map builders' pure pagination loops) or, worse,
    swallowed a wiring bug: the only
    `Shoko::Error` that `TextMetrics` can raise is `ConfigurationError` for an
    unconfigured runtime config, which the annotation-editor and
    dictionary-popup rescues converted into a silently degraded regex-strip
    render. Those now fail fast — composition configures TextMetrics on every
    entry path, so the error is always a wiring defect. `BackdropOverlay`'s
    `rescue Shoko::Error, StandardError` with a never-true `@resilient` flag
    (no constructor ever passed it) is deleted along with the flag. The
    rescue-conventions analyzer's `PROVABLY_NON_SHOKO_CALLS` table now also
    lists the never-raising Shoko primitives (`TextSanitizer.sanitize`,
    `sanitize_xml_source`, `HashNormalizer`, `RenderStyle.color`), so the
    pattern regresses loudly.
  - **The last two width-blind word-wraps are consolidated.** The 2026-07-10
    sweep's "wide input can no longer overflow the panels" had two surviving
    counterexamples, both measuring by `String#length`: the annotation
    editor's quote wrap (plus its char-based `ljust` padding) and the
    dictionary `EntryFormatter`'s sense/translation wrap. Both now use
    `Ui::TextUtils.wrap_prose`/`wrap_words` (display-width-aware, long words
    cell-wrapped) and `TextMetrics.pad_right`; wide-character regression specs
    cover both. `EntryFormatter` also lost its now-unused `color_mode:`
    parameter with the dead accent fallback.

- **2026-07-11 — Spec doubles verify for real; signature probing joins the reflection ban; the last duplicated primitives consolidated.**
  - **Mock verification is on and every `instance_double` names a real constant.**
    The suite had 435 `instance_double('Name')` doubles whose string names did
    not resolve (`'Document'`, `'Logger'`, `'ReaderStateReader'`, …) — under
    RSpec defaults each silently degraded to a permissive double, so ~95% of
    the suite's "verified" doubles verified nothing: the exact
    permissive-doubles trap the 2026-07-10 amendment blamed for silent feature
    death. Now `spec_helper` sets `verify_partial_doubles = true` and
    `verify_doubled_constant_names = true` (an unresolvable name is an error —
    the ratchet), and all 435 sites reference real constants (ports where the
    double stands in for an injected dependency; concrete classes elsewhere;
    `Proc` for the CLI factory lambdas). The conversion surfaced and fixed
    genuine drift: `ReaderLaunch::Contracts::PathResolution` declared only 2 of
    the 6 methods production calls (`canonical_path`, `canonical_recent_path`,
    `document_matches?`, `cache_pointer?` were missing);
    `Ports::Outbound::MenuBrowseInspection` lacked
    `selected_library_source_path` and `Ports::Outbound::ReaderDocument` lacked
    `chapters`, both called in production; specs stubbed a retired
    `dictionary_panel` field, a renamed `close_dictionary` method, and a
    `respond_to?` fossil of the removed probing.
  - **`no_reflection_probing` now bans signature probing everywhere in lib.**
    `x.method(:foo).parameters` / `klass.instance_method(:initialize).parameters`
    is the `respond_to?` trap through a different door — it defends against
    contracts the ports already pin and silently drops arguments when a
    signature drifts. All six sites were removed: the folder-import workflow
    and progress reporter call the `FolderImporter` port and the notifier
    contract (`PAYLOAD_KEYS`) directly; `CacheImportAdapter` type-checks a new
    `Ports::Outbound::DocumentWarmup` port instead of sniffing `#warm`;
    `BookImporterResolverAdapter` constructs importers through the uniform
    contract `new(progress_reporter:, runtime_config:)` (all five importers
    accept both; the dead `logger:` kwarg left the resolver port end-to-end);
    the FB2 parser's handler table dispatches statically (`title` is the one
    depth-aware element, handled explicitly). The guardrail's third example
    enforces the ban (`.parameters` / `arity`, whole lib, no allowlist).
  - **The scrollbar/ensure-visible/symbolize stragglers are consolidated.**
    The 2026-07-10 sweep covered the popup family but missed two hosts:
    `MenuDesign::CanvasList#thumb_metrics` (character-identical to
    `ListHelpers.scrollbar_thumb`) and the menu translator screen's third
    thumb variant plus a hand-rolled ensure-visible window — both now call
    `Ui::ListHelpers`. The eight hand-rolled `symbolize_keys`/`symbolize_hash`
    helpers re-implementing `Shared::HashNormalizer` are gone (each site
    delegates, preserving its own non-Hash behavior); `CatalogService` keeps
    its raising validation but delegates the normalization, and its
    `private`-masked class method became a plain private instance method
    (the `Lint/IneffectiveAccessModifier` todo entry is gone).

- **2026-07-10 — Dead event pipeline deleted; reflection-probing rule extended; popup primitives consolidated under R1's own bar.**
  - **The zero-subscriber event subsystem is gone.** `Application::State::EventBus`
    had no production subscriber — every `StateStore#update` built and emitted
    change events into the void, and the whole `Core::Events` tree
    (`DomainEventBus` + middleware pipeline, `EventFactory`, `BaseDomainEvent`,
    annotation/bookmark event classes) forwarded through `EventPublisherAdapter`
    into that same void (~700 LOC, kept alive only by its own unit specs). All of
    it is deleted; `ObserverStateStore`'s path observers — the mechanism that
    always carried production traffic — are the single notification path.
    `StateStore` no longer takes an event bus; `AnnotationService` and
    `BookmarkService` lost their `domain_event_bus`/`domain_event_factory`
    dependencies. If domain events become a real requirement, design them for a
    real consumer; git preserves the old shape.
  - **`no_reflection_probing` now also covers adapters + shared.** Probing an
    injected collaborator for a method its contract guarantees
    (`x.respond_to?(:foo) && x.foo`) is a silent-failure trap: a rename passes
    every test against permissive doubles while the feature quietly dies. ~35
    such probes were removed (event loop → controller, menu controller → catalog,
    input router → ui controller, screens → typed dependency records, session
    adapters → popups, state readers for schema-guaranteed fields); the affected
    spec doubles were completed instead. `respond_to?` survives only at genuine
    polymorphic/external boundaries (protocol-conversion probes on values, plus
    an explicit per-file allowlist in the spec, each entry justified).
  - **The bottom-docked popup family's primitives are consolidated.** R1's own
    bar ("used by two or more call sites") had been met — and ignored — by
    copy-pasted `wrap`/`wrap_indices`, `scrollbar_thumb`, `ensure_*_visible!`,
    and `seg`/`cell`/`dim_line`/`body_line`/`render_rule` across the five
    popups, with drift (three `scrollbar_thumb` variants; a dead prose-wrap in
    notes missing the long-word split). Now: `Ui::TextUtils.wrap_prose` /
    `.wrap_indexed` (display-width-aware, so wide input can no longer overflow
    the panels), `Ui::ListHelpers.scrollbar_thumb` / `.scroll_to_reveal`, and
    the `Ui::PanelSpans` mixin (a genuine ≥2-host mixin with per-host palette
    hooks) — each unit-tested in isolation. The dictionary *setup wizard* keeps
    its deliberate styled-input-safe variants; it is a different family.

- **2026-06-23 — R1 fully enforced: the two deferred protocol redesigns landed.**
  The last two `no_include_once_mixin` ALLOWLIST holdouts are gone; the scanner
  allowlist now contains only the §IV composition-wiring files and the
  reader_launch type contracts.
  - **Dictionary install wizard.** `dictionary/setup_flow_support` +
    `dictionary/language_pair_support` (two modules mixed once into
    `DictionaryController`, sharing `@setup_session` and calling back into ~8
    controller methods) became `Dictionary::SetupSession` — a real collaborator
    that owns the wizard state (`@setup_session`, the per-book manual-source
    memory) and the language/pair logic, built from the controller's own typed
    dependency groups and unit-tested in isolation
    (`setup_session_spec`). The controller now drives it through a small public
    surface (`begin_lookup`, `present_result`, `resolve_pair`, `handle_*`,
    `clear`). Their `*_support` names also leave the `naming_banlist` allowlist.
  - **Reader text selection / right-click menu.** `selection_mouse_handler`
    (a module mixed once into `MouseableReader`, reaching the host's ivars
    through `defined?(@ivar)` probes and sharing its mutable
    `@selected_text` / `@suppress_popup_release_once`) was **inlined** into
    `MouseableReader` as private methods — the constitution's R1 first option,
    correct here because the behavior is bound to that one host's mouse state
    machine (the census itself called it "not a separable collaborator"). The
    fragile `smh_*`/`defined?` accessors collapse to direct ivar reads; the
    isolated spec now exercises the real host via `allocate`.

- **2026-06-12 — §IV executed: census-P2 flattening landed; require-climb rule live.**
  The two allowlisted deep prefixes are gone and both §IV rules are enforced
  with **empty allowlists** (`directory_depth` spec):
  - The reader TOC component tree (`adapters/ui/components/sidebar/toc/**`,
    23 files) was **deleted, not flattened** — it was dead code. The sidebar
    TOC tab was retired when the TOC moved to the bar mode (which uses
    `Core::Services::TocTreeService`), but the tab's render tree, its
    `TocNavigation` input chain, the unbound `:open_toc_sidebar`/`:toggle_sidebar`
    intents, four `sidebar_toc_*` state fields, and the mouse scroll/drag/click
    paths all survived unreachably. The schema even still defaulted
    `sidebar_active_tab` to `:toc`. All of it is excised; the sidebar tab
    default is `:annotations`; valid tabs are `[annotations, bookmarks]`.
  - The composition assembler tree (`.../controller_builder/ui_graph_builder/**`)
    collapsed into the single flat `ui_graph_builder.rb` wiring file — §IV's
    endorsed "few longer, boring wiring files" shape.
  - **Require-climb mechanism clarified:** "move the file" applies to climbs
    within a file's own area. Cross-layer references from legitimately-placed
    files cannot satisfy ≤2 climbs by moving, so far references use load-path
    requires (`require 'shoko/...'`); the lib root is on `$LOAD_PATH` from
    every entry point (bin/shoko, lib/shoko.rb, spec_helper, the
    isolated-require harness), and Ruby dedupes `require`/`require_relative`
    by realpath so the styles coexist safely. All 526 pre-rule climbing
    requires were converted; the guardrail enforces ≤2 with no allowlist.

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

- **2026-07-18 — The state store's "immutable" claim becomes an enforced
  frozen-tree invariant.** The store called itself an "immutable-snapshot state
  store" while returning its live internal tree unfrozen from
  `peek`/`peek_at`/`get`: any caller could mutate state in place, bypassing
  validation, locking, change sets, and observers — and identity-cached
  snapshot adapters would then serve stale data. Copy-on-write also duplicated
  only Hash nodes, structurally sharing arrays, and schema fragments
  contributed shallow-dup'd `DEFAULTS`, so independently built containers
  shared the same mutable default arrays. Now: the composed initial tree is
  deep-frozen; `apply_updates` deep-dups and freezes inserted values (callers
  keep ownership of their arguments) and freezes every path-copied node before
  commit, keeping the whole tree frozen at O(path + value) cost; schema
  fragments freeze their mutable literal defaults; snapshot defaults are
  deep-frozen in `SnapshotFactory.define_snapshot`. Non-data leaf objects
  (anything that is not Hash/Array/String) are opaque: the store never freezes
  domain objects. The shared primitive is `Shoko::Shared::DeepStructure`. The
  `state_conventions` guardrail enforces the invariant end-to-end: every data
  node frozen after build and update, out-of-band mutation raises, inserted
  values are dup'd, no mutable structure shared between stores, fragment
  defaults deep-frozen.

- **2026-07-18 — R1 closes the `extend` hole; TextMetrics reunified.** R1's
  text and scanner covered only `include`/`prepend`, so `TextMetrics` had been
  split into five modules (`RuntimeControls`, `Caching`, `Measurement`,
  `Truncation`, `Wrapping`) each `extend`ed into exactly one host — singleton-
  class mixin fragmentation, functionally identical to what R1 forbids and
  invisible to its enforcement. R1 now names `extend` explicitly, the scanner
  matches it (`extend self` stays exempt as the module-function idiom, and the
  widened scan found no other offenders), and the five fragments are inlined
  back into `shared/terminal/text_metrics.rb` as one flat module with private
  internals (R2: its ~570 lines are not a reason to split). The rule text now
  also names the scanner ALLOWLIST as its own exemption list, so the law and
  its executable enforcement can no longer drift apart silently.

- **2026-07-18 — §III's one-constant-per-file rule gets its missing
  enforcement.** The rule ("a file is named after the single class/module it
  defines") had no guardrail; the naming spec checked only banned suffixes and
  shorthand declarations. Fifteen files had accumulated sibling constants —
  worst, `archive/zip_reader.rb` held the entire 22-constant `Shoko::Zip`
  subsystem while the actual `ZipReader` facade hid in a file named
  `facade.rb`. Now `SingleConstantFileScanner` (naming_banlist spec) enforces:
  one root constant per file, short name matching the basename
  (case-insensitive, so `CLI`/`EOCDParser` need no acronym table;
  directory-scoped prefixes like `opf/navigation_selector.rb` →
  `OPFNavigationSelector` allowed), everything else nested inside it.
  Namespace reopenings, require-only aggregators, and values-only files
  (version.rb, route tables) are out of scope. **Codified exemption:**
  `shared/errors.rb` — the sealed error taxonomy is one domain concept;
  eighteen three-line files would be noise, not decomposition. The offenders
  were split file-per-constant (`Shoko::Zip` → `archive/zip/`, the reader
  dependency records, the terminal input decoder collaborators, the core
  model siblings, overlay/pagination/search types), private `*SnapshotInternal`
  scaffolding modules became local variables, and `ui_constants.rb`/`facade.rb`
  were renamed to match what they define.

- **2026-07-18 — The plain require surface becomes lazy, with a budget.**
  `require 'shoko'` eagerly loaded 369 files (~0.2-0.3 s) because
  `lib/shoko.rb` required the container factory's registration wall; even
  `--help` paid the full cost, and `bin/shoko` called
  `ContainerFactory.build_process_control` before parsing a single option.
  Now `lib/shoko.rb` requires only version, errors, and the CLI adapter, and
  declares `autoload` for the composition/application entry constants
  (`ContainerFactory`, `RuntimeComposition`, `FormatRegistryComposition`,
  `UnifiedApplication`) — the full graph loads on first reference, exactly as
  before in behavior but only when actually used. Measured: 7 files / ~9 ms
  on plain require; `shoko --help` ~55 ms end-to-end; a container build pulls
  the graph on demand; `SHOKO_TEST_MODE`/`SHOKO_EAGER_BOOT` still eager-boot
  the manifest (the spec suite runs fully eager). Format registration moved
  from require time into `create_default_container` (idempotent), the CLI
  defaults its own `process_control`, and the dead `build_process_control`
  seam is gone. The boot-surface guardrail now enforces a **total budget**
  (≤20 files on plain require) alongside the existing denylist, so
  re-eagering the graph fails the suite by an order of magnitude instead of
  needing a listed filename.

- **2026-07-18 — Aggregate coupling becomes measurable; dependency bags stop
  concealing it; "outbound" regains its meaning.** Typed dependency records
  had made constructor budgets look healthy while hiding aggregate coupling:
  the menu controller took 3 records carrying 22 leaf dependencies (two of
  them — file_probe, path_ops — write-only dead fields), acted as a service
  locator (menu_builder read settings_service/annotation_service/catalog back
  off the controller's public readers; MainMenuComponent pulled
  observer_registry/catalog off the controller instead of its own
  dependencies), and ReaderUiDependencies (21 fields) existed only to be
  repackaged by the render coordinator into the 16-field RenderDependencies
  at draw time, with 4 fields dead in transit. Changes:
  - Menu controller: dead fields removed; services the controller never used
    rerouted from the composition context; observer wiring moved to the
    composition root (controller drops observer_registry and clock); the
    component-factory-plus-13-field-bag pass-through replaced by a closure
    built in menu_builder. Aggregate: 22 → 17, with the locator surface
    (settings_service/annotation_service/observer_registry readers) gone.
  - Reader side: ReaderUiDependencies deleted. RenderDependencies is built
    fully formed at the composition root and injected; the render
    coordinator no longer repackages, and the assembler passes
    view_model_builder_factory explicitly.
  - The constructor-budget guardrail now ALSO ratchets **aggregate leaf
    dependencies** per coordinating class (records summed + direct extras),
    frozen at post-refactor actuals (Menu::Controller 17, MouseableReader 44,
    UIController 19, MenuUiDependencies 14, RenderDependencies 16) —
    shrink-only. Satisfying per-record caps by re-bagging no longer works.
  - **Port doctrine:** an outbound port is a contract implemented by an
    adapter. Contracts implemented only by application-layer objects are
    internal role interfaces and live under `application/ports/internal/`
    (ReaderDocument, DocumentLoader, DocumentWarmup moved). The
    ports-contract guardrail enforces both directions: an outbound port
    without an adapter implementer and an internal port with one are each
    violations.

- **2026-07-18 — Completeness pass: the 2026-07-18 remediation's claims are
  made true where they were only mostly true.** An external re-audit found
  gaps between declared and enforced properties; each is now closed:
  - **State admissibility.** `DeepStructure` recursively copies/freezes
    `Struct` (member-copied, no initializer re-run) and freezes `Data`
    instances and their members in place; mutable Structs such as
    `SearchMatch` can no longer ride into state unfrozen. Opaque leaves must
    be frozen or expose no public writers — the state-conventions guardrail
    walks Struct/Data members and enforces the writer ban.
  - **Network ceilings at every boundary.** The dictionary catalog (index +
    downloads), Libgen (mirror pages + downloads), and LibreTranslate
    (success and error bodies) gained byte ceilings; the translation-model
    limit is now `min(catalog-declared, absolute)` so a compromised catalog
    cannot grant itself a bigger budget. Every `Net::HTTP` user in lib is
    bounded.
  - **Relay bookkeeping.** Each `AsyncResultRelay` submission carries a
    once-only finisher; an executor that runs the block inline and then
    raises from `#submit` can no longer consume another job's pending count.
  - **Scanner soundness.** The R1 scanner matches parenthesized and
    `::`-qualified mixin sites; the single-constant scanner treats CamelCase
    assignments as definitions (a misnamed `Data.define` is an offense) and
    only accepts exact or parent-directory-prefixed names. Both have parsing
    unit tests inside their rule specs. The ports guardrail matches every
    qualification spelling of a port include; the unconsumed
    `DynamicPageSource` marker interface (one app-layer includer, zero
    consumers) is deleted.
  - **Aggregate ratchet.** Counts are transitive (nested dependency records
    flatten to their leaves — MouseableReader is honestly 46, not 44) and
    pins are exact: any drift fails, and pins may only ever be edited
    downward. `MenuUiDependencies` dropped its three consumerless fields
    (rss_reader_service, reader_launch_state, document): 14 → 11.
  - **TextMetrics.** Re-decomposed per R3 into collaborator objects —
    `RuntimeControls`, two cache classes, `Measurer`, `Truncator`,
    `Wrapper`, each with isolated unit specs — behind the stable
    `TextMetrics` facade. Distinct state and roles, no single-host mixins,
    no 570-line module.
  - **Zip hygiene.** The two spurious `require_relative 'file'` edges (an
    artifact of the mechanical split matching `::File`) are gone, and
    `File.close_safely` rescues what close can actually raise
    (IOError/SystemCallError) instead of the impossible `Shoko::Error`.
  - The plain-require boot budget tightened from 20 to 10 files.

- **2026-07-18 — Second completeness pass: a further re-audit found the first
  one still overstated three properties; each is now closed or honestly
  scoped.**
  - **State admissibility is a closed contract.** `DeepStructure.admit` (the
    store's write transform) copies Hash KEYS as well as values, rebuilds
    `Data` values via `new(**to_h)` so the caller's instance and members stay
    untouched (the previous in-place member freezing violated the
    callers-keep-ownership contract), and REJECTS unfrozen opaque leaves with
    `InadmissibleValueError` — a reader-only wrapper around a mutable array
    can no longer ride into state. `frozen?` is the strongest lib-side check
    without reflection; the guardrail additionally reflection-walks admitted
    value objects verifying deep frozenness. The dictionary value objects
    (DictionaryEntry/DictionaryResult/FuzzyMatch) are born frozen — the only
    production classes stored as opaque leaves.
  - **Ceilings are hard.** Every bounded reader and download loop checks
    `current + chunk` BEFORE appending or writing, matching the
    model-catalog downloader's ordering — no chunk of overshoot is ever
    buffered or written.
  - **Scanners are AST-backed where line regexes lied.** Mixin sites (R1)
    and port includes come from the Ripper-based `MixinSiteExtractor`:
    multi-argument (`include A, B`), parenthesized, multiline, and
    `::`-anchored spellings are seen exactly as Ruby sees them, and
    top-level anchoring is honored during resolution. The single-constant
    scanner counts `CONST = Data.define/Struct.new/...` as a definition
    regardless of casing (`URL = Data.define` is no longer invisible).
  - **The menu locator surface is gone below the component too.** Every menu
    screen now declares its exact collaborators as keywords
    (`menu_state_reader:`, `menu_hit_registry:`, …); the 11-field
    `MenuUiDependencies` bag stops at `MainMenuComponent`, and no screen
    holds a bag or reaches through `dependencies&.`.
  - **The aggregate ratchet states its scope**: enumerated classes with an
    explicit nested-record map and exact pins — a curated review ratchet,
    not universal constructor analysis. The wrap cache is a true LRU (hits
    refresh recency) and returns the same frozen value on miss and hit;
    RuntimeControls and both caches have isolated unit specs, making the
    "every collaborator unit-tested" claim true. `Zip::File.close_safely`
    has a regression spec. The constitution's own "oracle"/"DONE" language
    is scoped to architectural shape — conformance is not correctness, and
    green guardrails do not replace adversarial review.

- **2026-07-18 — Third completeness pass: enforcement now matches the closed
  contracts rather than their earlier approximations.**
  - **State values are structurally closed at both entrances.** Initial schema
    output and every update now go through the same `DeepStructure.admit`
    transform. It accepts only exact intrinsic primitives, unadorned plain
    String/Array/Hash containers, and Struct/Data values whose complete
    instance state is in declared members; all keys, elements, and members are
    copied recursively and the result is independently verified frozen.
    Opaque objects (frozen or not), mutable Numeric subclasses, hidden ivars or
    singleton behavior, special-semantics Hashes, and cycles are rejected.
    Data reconstruction reads `Data#to_h` directly rather than a domain
    serialization override. DictionaryEntry, DictionaryResult, and FuzzyMatch
    are Data value objects, so no opaque-leaf exception remains.
  - **Mixin enforcement resolves what it counts.** The Ripper inventory covers
    direct and explicit-receiver include/prepend/extend calls, multiple
    arguments, parentheses, multiline calls, literal-array splats, the common
    `send` forms, constant aliases, and top-level anchoring. A statically
    unresolved target is a violation rather than a silently omitted site.
    Widening that inventory exposed the dynamic one-use AliasReaders mixin;
    `Reader::ControllerInterface` was removed and its sole-host delegation
    contract now lives directly on ReaderController under R1/R2/R3. The ports
    guardrail consumes the same canonical inventory instead of applying a
    second regex interpretation. Constant assignments in the one-constant
    scanner are also Ripper-derived, including qualified and multiline aliases
    and top-level-qualified/multiline type constructors.
  - **One-use UI state is not disguised as a collaborator.** The sole-host
    AnnotationEditState projection was folded into
    AnnotationEditScreenComponent as private behavior, with edit, save,
    refresh, and return-mode regression coverage.
  - **Ceiling ordering is executable behavior, not just source ordering.**
    Focused tests feed non-appendable oversized chunks to every bounded buffer
    and both decompression paths, and writer/hash spies to every download
    stream. They prove the failing chunk reaches neither memory buffers, disk,
    nor the model digest before the error.
  - **The wrap memo owns every object it retains and returns.** Its LRU key is
    copied/frozen before both lookup and reinsertion; disabled and oversized
    bypasses return the same deep-frozen line shape as hits and misses.
