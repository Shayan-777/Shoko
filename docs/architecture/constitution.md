# Shoko architecture policy

This file is the active policy. It states invariants, not the story of how they
were discovered. Historical context and decisions live under
`docs/architecture/history/` and `docs/architecture/decisions/`.

## 1. Dependency direction

Shoko uses four production areas:

- `core/` contains domain data and deterministic domain behavior. It depends on
  Ruby and `shared/`, never on application, adapters, or composition.
- `application/` owns use cases, workflows, state coordination, and ports. It
  may depend on core and shared, never on concrete adapters or composition.
- `adapters/` translate files, terminals, networks, clocks, storage, and UI
  events. They may implement application ports. Cross-adapter dependencies must
  represent an intentional subsystem relationship rather than convenience.
- `composition/` is the only place that chooses concrete implementations and
  assembles the object graph.

Dependencies point inward. A rename, require, or constant reference counts as a
dependency even when hidden behind a helper.

## 2. Ports

Create a nominal port only when at least one of these is true:

- the application needs an external capability;
- multiple independently replaceable implementations exist or are expected;
- a process, persistence, network, clock, terminal, or UI boundary is crossed;
- the interface is a stable application entry point.

Do not create ports merely to rename an internal method call, satisfy a diagram,
or make every constructor argument nominal. Internal role interfaces belong in
`ports/internal`; external capabilities in `ports/outbound`; application entry
points in `ports/inbound`. Every nominal port has a production implementation.

## 3. Decomposition

Decompose by ownership of state and change:

- A collaborator owns a coherent state machine, policy, resource lifecycle, or
  transformation and exposes a small callable surface.
- A module is appropriate for genuine shared protocol behavior. A one-host
  module is normally evidence that the behavior belongs in its host or in a
  collaborator object, but it is not forbidden by cardinality alone.
- File size, directory depth, constructor arity, and dependency count are review
  signals. They are not substitutes for cohesion analysis.
- Dependency records group capabilities that change together. They must not be
  used to conceal an incoherent object graph.

Prefer explicit delegation over shared private instance variables. Avoid class
reopening across files when an ordinary nested constant or collaborator works.

## 4. Imported data and resources

Treat every imported book, feed, cache file, archive entry, XML tree, compressed
stream, image, and metadata field as hostile input.

- Enforce a source-size limit before parsing.
- Bound each decompressed item and the aggregate expansion for one import.
- Bound structural work such as records, XML events, nesting, dimensions, and
  recursive references.
- Reject the input when a limit is exceeded; never silently truncate structural
  data into a plausibly valid document.
- Validate paths before filesystem access and keep archive entries inside their
  intended root.

Limits live in one format-facing budget policy and are exercised by adversarial
tests. A parser-specific lower bound is allowed; an unbounded parser is not.

## 5. Errors and resilient boundaries

Catch the narrowest exception set that the operation can recover from. Catch
`StandardError` only at a deliberate containment boundary and mark that branch
with `# resilient-boundary`.

A containment boundary must:

- preserve fatal external-input errors when continuing would be unsafe;
- return an explicit fallback or failure result;
- keep diagnostics best-effort and non-throwing;
- complete synchronization bookkeeping in `ensure`;
- prevent one observer, logger, cleanup hook, or background job from starving
  unrelated work.

Never rescue `Exception`, `Object`, or `BasicObject`.

## 6. Concurrency and lifecycle

- UI state is applied on the UI thread.
- Worker results cross through an injected relay or executor contract.
- Request generations invalidate stale asynchronous results.
- Notification queues acknowledge every envelope exactly once, including when
  observers or diagnostics fail.
- Terminal modes, mouse tracking, files, locks, workers, and child processes are
  released in `ensure` or an equivalent idempotent lifecycle object.

## 7. Composition

Composition is explicit, deterministic, and side-effect-light:

- registration files or their adjacent boot manifest own the requires for the
  concrete services they register;
- the top-level factory shows registration order and application entry points;
- lazy loading is used only for a measured boot-surface reason;
- no runtime service locator is passed into domain or application objects;
- construction failures fail fast with the missing contract named.

## 8. Dependencies

Third-party runtime gems are permitted when they improve correctness, security,
maintenance, or interoperability over an in-house implementation. Each runtime
dependency requires a record in `runtime-dependencies.yml` with its requirement,
rationale, owner, and review date. "Zero dependencies" is a current property,
not an architectural objective.

## 9. Guardrails

Architecture tests enforce a small number of high-value invariants:

- all scanned files are readable and parseable; scanner errors fail the suite;
- dependency direction and core/application purity hold;
- ports are placed correctly, implemented, and aligned with intent handlers;
- constructors stay reviewable;
- state ownership and composition wiring remain explicit;
- resilient boundaries follow section 5;
- production code does not use reflection to make dependencies optional.

Do not add scanners for naming taste, raw line count, directory depth, semantic
similarity, or a one-time migration. Add a guardrail only for a durable failure
mode, with a regression fixture proving it detects the bad case. Remove a rule
when its premise is no longer policy.

## 10. Completion

A change is complete when relevant focused tests, architecture tests, lint, and
the full required suite pass. Tests must cover the failure mode, not private
implementation trivia. Update policy only when the durable rule changes; record
the reason in an ADR rather than appending amendments here.
