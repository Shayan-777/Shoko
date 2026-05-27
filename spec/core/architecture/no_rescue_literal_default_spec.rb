# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'No rescue literal defaults' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  # Audited per-case exemptions, matched by file path (the analyzer's
  # `path:line` is checked against each prefix). Each exempt file has a
  # single audited rescue site; the comment names the legitimate
  # semantic, and the rescue itself carries the same rationale in code.
  # Matching by file (not file:line) avoids brittle line-number drift
  # when surrounding comments change. Trade-off: a SECOND rescue → literal
  # added to one of these files is silently accepted by this guard, so
  # any new rescue in these files needs explicit review.
  #
  # ── Exemption-criteria principle ─────────────────────────────────────
  # The default position is that rescue branches must fail fast or
  # translate context, not return literals. Two narrow categories of
  # legitimate exception are accepted:
  #
  # 1. ADAPTER CONTRACT FULFILLMENT. An adapter implementing an outbound
  #    port translates external-system exceptions into the port's typed
  #    contract. If the port promises "returns a value or nil," and the
  #    underlying I/O can raise, the adapter's `rescue` → nil IS the
  #    contract; the application sees only the typed value. This is the
  #    correct architectural role of an adapter and is permitted at the
  #    adapter boundary only.
  #
  # 2. DOMAIN SEMANTIC EQUIVALENCE. A pure helper where the literal IS
  #    the correct domain answer for the rescued case (not a placeholder
  #    for unhandled error). The clearest signal: replacing the rescue
  #    with `raise` would force every call site to duplicate the same
  #    "convert to literal X" transformation. Examples: "unparseable
  #    timestamp = expired", "parse-utility returns nil so a fallback
  #    strategy can run".
  #
  # What is NOT a legitimate exception: APPLICATION-LAYER swallow-into-
  # literal patterns. Those are symptom suppression — the application
  # should either translate to a typed application error or let the
  # adapter's contract surface the right typed value. Adding an
  # `application/**` file to this list requires justification beyond
  # case-by-case judgment.
  EXEMPT_FILES = [
    # `cache_expired?`: an unparseable timestamp is semantically
    # equivalent to "expired" — the literal `true` is the correct domain
    # answer, not an unhandled error. Pre-validating with a regex doesn't
    # cover edge cases like `2024-02-30` that Time.iso8601 still rejects.
    'adapters/book_sources/book_finder.rb',

    # `parse_xml`: parse-utility contract returns nil when REXML rejects
    # the input. The nil is the signal that drives the wrapped-fragment
    # fallback in `parse_navigation_document`.
    'adapters/book_sources/epub/parser/opf/navigation_document_scanner.rb',

    # `delete_cache_file`: best-effort cleanup of a stale/corrupt cache
    # file during a read path. SystemCallError (e.g. permission denied
    # on the cache dir) translates to nil so the read doesn't crash; the
    # validity check will reject the entry on the next read anyway.
    'adapters/storage/repositories/display_metadata_cache_repository.rb',

    # `FileProbeAdapter#mtime`: adapters are the layer where filesystem
    # exceptions translate into typed values for the application. The
    # FileProbe port promises mtime returns either an ISO 8601 string or
    # nil; the rescue here implements that contract by converting
    # SystemCallError into nil.
    'adapters/storage/file_probe_adapter.rb',
  ].freeze

  it 'forbids fallback literal defaults directly after rescue branches' do
    offenders = SpecSupport::Architecture::RescueGuardrailAnalyzer.fallback_literal_rescue_offenders(
      lib_root:
    )
    offenders = offenders.reject do |entry|
      EXEMPT_FILES.any? { |exempt| entry.start_with?("#{exempt}:") }
    end

    expect(offenders).to eq([]),
                         "Rescue branches must fail fast instead of returning literal defaults:\n#{offenders.join("\n")}"
  end
end
