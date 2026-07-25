# frozen_string_literal: true

require 'spec_helper'

# Consolidated rescue/fallback conventions (constitution §V: one spec per rule
# *family*; §VIII: resilient boundaries). Each example delegates to the shared
# RescueGuardrailAnalyzer or scans directly. Absorbs the former per-rule
# micro-specs: no_standard_error_rescue, no_rescue_exception, no_bare_string_raise,
# no_noop_reraise_rescue, no_overlapping_rescue_chains, no_rescue_numeric_default,
# no_implicit_null_runtime_config, no_stale_optional_resolution,
# no_swallowing_rescue, no_rescue_literal_default, no_proc_type_fallbacks, the
# fail-fast unreachable-raise rule, the zero-fallback inline-rescue rules, and
# the hardening-scope resilient-boundary marker rule.
RSpec.describe 'Rescue and fallback conventions' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:analyzer) { SpecSupport::Architecture::RescueGuardrailAnalyzer }

  def rel(path)
    path.delete_prefix("#{root}/")
  end

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  it 'requires rescue StandardError branches to fail fast with explicit translation/raising' do
    offenders = analyzer.standard_error_rescue_without_translation_offenders(lib_root:)
    expect(offenders).to eq([]),
                         "rescue StandardError must immediately raise/translate failures:\n#{offenders.join("\n")}"
  end

  it 'requires resilient-boundary markers to annotate rescue StandardError branches' do
    offenders = analyzer.mismarked_resilient_boundary_offenders(lib_root:)
    expect(offenders).to eq([]),
                         "# resilient-boundary must sit directly above a `rescue StandardError` branch — " \
                         "a narrower class cannot deliver the containment the marker promises:\n#{offenders.join("\n")}"
  end

  # Constitution §VIII (R4): the marker documents swallowing isolation points.
  # Broad rescues whose body re-raises are translation sites, not resilient
  # boundaries, and must NOT carry the marker — they are exempt here.
  it 'requires explicit resilient-boundary annotation for swallowing broad rescues in boundary scope' do
    files = Dir[File.join(lib_root, 'application', 'workflows', '**', '*.rb')] +
            Dir[File.join(lib_root, 'adapters', 'input', 'controllers', 'menu', '**', '*.rb')] +
            Dir[File.join(lib_root, 'adapters', 'runtime', 'session_state', '**', '*.rb')]

    offenders = []
    files.each do |path|
      lines = File.readlines(path)
      lines.each_with_index do |line, index|
        next unless line.match?(/\brescue StandardError\b/)

        prev = index.positive? ? lines[index - 1] : ''
        next if prev.include?('# resilient-boundary')
        next if broad_rescue_body_reraises?(lines, index)

        offenders << "#{rel(path)}:#{index + 1}"
      end
    end

    expect(offenders).to eq([]),
                         "Swallowing broad rescues in boundary scope require '# resilient-boundary':\n#{offenders.join("\n")}"
  end

  # Constitution §VIII (R4): rescue breadth must match what the guarded code
  # can actually raise. A `rescue Shoko::Error` directly over a JSON parse or
  # raw file read is the regression that has bitten this codebase twice — the
  # stdlib error (JSON::ParserError, Errno::*) is not a Shoko::Error and
  # escapes the handler that claims to contain it.
  it 'forbids rescue Shoko::Error directly over a call that cannot raise Shoko::Error' do
    offenders = analyzer.narrow_shoko_rescue_over_stdlib_offenders(lib_root:)
    expect(offenders).to eq([]),
                         "rescue Shoko::Error cannot contain stdlib failures — rescue the real classes, " \
                         "rescue StandardError at a resilient boundary, or translate at the source:\n#{offenders.join("\n")}"
  end

  it 'forbids rescue Exception in lib/shoko runtime sources' do
    offenders = analyzer.exception_rescue_offenders(lib_root:)
    expect(offenders).to eq([]), "rescue Exception is not allowed in runtime code:\n#{offenders.join("\n")}"
  end

  it 'forbids raise with string literals in lib/shoko runtime sources' do
    offenders = analyzer.bare_string_raise_offenders(lib_root:)
    expect(offenders).to eq([]), "raise with string literal is not allowed in runtime code:\n#{offenders.join("\n")}"
  end

  it 'forbids rescue branches that only re-raise without translation or context' do
    offenders = analyzer.no_op_reraise_rescue_offenders(lib_root:)
    expect(offenders).to eq([]), "No-op rescue re-raises must be removed:\n#{offenders.join("\n")}"
  end

  it 'forbids overlapping rescue classes after explicit re-raise in same rescue chain' do
    offenders = analyzer.overlapping_rescue_chain_offenders(lib_root:)
    expect(offenders).to eq([]),
                         "Overlapping rescue chains with explicit re-raise produce unreachable handlers:\n#{offenders.join("\n")}"
  end

  it 'forbids unreachable code after unconditional raise in rescue blocks' do
    offenders = []
    Dir[File.join(lib_root, '**', '*.rb')].each do |path|
      lines = File.readlines(path)
      lines.each_with_index do |line, index|
        next unless line.match?(/^\s*rescue\b/)
        next unless lines[index + 1]&.match?(/^\s*raise\s*$/)

        cursor = index + 2
        while cursor < lines.length
          current = lines[cursor]
          break if current.match?(/^\s*(rescue|else|ensure|end)\b/)

          text = current.strip
          if !text.empty? && !text.start_with?('#')
            offenders << "#{rel(path)}:#{index + 1}"
            break
          end
          cursor += 1
        end
      end
    end

    expect(offenders).to eq([]),
                         "Unreachable rescue branches detected:\n#{offenders.sort.join("\n")}"
  end

  it 'forbids rescue branches that default to numeric literals' do
    offenders = analyzer.numeric_default_rescue_offenders(lib_root:)
    expect(offenders).to eq([]), "Rescue branches must not hide failures with numeric defaults:\n#{offenders.join("\n")}"
  end

  # Audited per-case exemptions, matched by file path. Each exempt file has a
  # single audited rescue site; the rescue itself carries the rationale in code.
  #
  # ── Exemption-criteria principle ─────────────────────────────────────
  # The default position is that rescue branches must fail fast or translate
  # context, not return literals. Two narrow categories of legitimate
  # exception are accepted:
  #
  # 1. ADAPTER CONTRACT FULFILLMENT. An adapter implementing an outbound port
  #    translates external-system exceptions into the port's typed contract.
  #    If the port promises "returns a value or nil," the adapter's
  #    `rescue` → nil IS the contract.
  #
  # 2. DOMAIN SEMANTIC EQUIVALENCE. A pure helper where the literal IS the
  #    correct domain answer for the rescued case (e.g. "unparseable
  #    timestamp = expired").
  #
  # APPLICATION-LAYER swallow-into-literal patterns are NOT legitimate —
  # adding an `application/**` file here requires justification beyond
  # case-by-case judgment.
  LITERAL_DEFAULT_EXEMPT_FILES = [
    # `cache_expired?`: an unparseable timestamp is semantically equivalent
    # to "expired" — the literal `true` is the correct domain answer.
    'adapters/book_sources/book_finder.rb',

    # `parse_timestamp`: a corrupt/hand-edited stored progress timestamp is
    # semantically "unknown last-read time" — the literal `nil` is the correct
    # domain answer (and sorts to epoch in `recent_books`). Time.parse raises
    # ArgumentError on garbage, which is not a Shoko::Error.
    'adapters/storage/repositories/progress_repository.rb',

    # `load_json_or_empty`: a corrupt/truncated/externally-synced sidecar store
    # (annotations/bookmarks/progress) is semantically "no data yet" — the
    # literal `{}` is the correct domain answer, so a single bad file never
    # blocks opening the book. JSON::ParserError/Errno are not Shoko::Error;
    # recent.json and rss_reader.json already rescue identically at their load.
    'adapters/storage/repositories/storage/file_store_utils.rb',

    # `load`: recent.json follows the same sidecar read discipline as
    # file_store_utils above — a transiently unreadable history file is
    # semantically "no recent entries right now", and the read-only path must
    # never block the menu or a launch. Mutations do NOT share this rescue:
    # `load_for_update` translates the same access errors into StorageError
    # so a save can never flatten the history.
    'adapters/storage/recent_files_repository.rb',

    # `parse_xml`: parse-utility contract returns nil when REXML rejects the
    # input; the nil drives the wrapped-fragment fallback.
    'adapters/book_sources/epub/parser/opf/navigation_document_scanner.rb',

    # `delete_cache_file`: best-effort cleanup of a stale/corrupt cache file;
    # SystemCallError translates to nil so the read doesn't crash.
    'adapters/storage/repositories/display_metadata_cache_repository.rb',

    # `FileProbeAdapter#mtime`: the FileProbe port promises an ISO 8601
    # string or nil; the rescue implements that contract.
    'adapters/storage/file_probe_adapter.rb',

    # `emit`: the progress stream is a best-effort sink by contract — when
    # the parent menu cancels the batch and closes the pipe, progress has
    # nowhere to go and the pagination work itself must keep its value.
    'adapters/runtime/prepagination_progress_stream_adapter.rb',

    # `decompress`: a body whose compressed encoding does not parse is
    # semantically "not actually compressed" (servers mislabel
    # Content-Encoding); the raw body is the correct domain answer. The
    # fetchers historically implemented the identical fallback, laundered
    # through an `undecoded_body(body)` wrapper the analyzer couldn't see —
    # this exemption states the same judgment honestly. Over-limit
    # expansion is NOT rescued: TooLarge always propagates.
    'adapters/rss/bounded_http_body.rb',

    # `sqlite3_available?`: a predicate's contract is to answer its question,
    # and "the optional gem is not installed" is the false case rather than a
    # swallowed failure. Previously this raised and the reader controller
    # laundered the literal through a `dictionary_lookup_unavailable?` wrapper
    # returning `false` — invisible to the analyzer, exactly the pattern the
    # bounded_http_body entry above describes — while the three call sites
    # that did NOT rescue turned a missing gem into a crash. Answering
    # honestly here is the fix; this exemption states that judgment openly.
    'adapters/storage/sqlite_dictionary_adapter.rb',
  ].freeze

  it 'forbids fallback literal defaults directly after rescue branches' do
    offenders = analyzer.fallback_literal_rescue_offenders(lib_root:)
    offenders = offenders.reject do |entry|
      LITERAL_DEFAULT_EXEMPT_FILES.any? { |exempt| entry.start_with?("#{exempt}:") }
    end

    expect(offenders).to eq([]),
                         "Rescue branches must fail fast instead of returning literal defaults:\n#{offenders.join("\n")}"
  end

  # Fatal external input is designed to terminate (shared/errors.rb): any
  # rescue of FatalExternalInputError must end in termination or a re-raise.
  FATAL_RESCUE_FILES = [
    'lib/shoko/adapters/input/cli.rb',
    'lib/shoko/adapters/input/controllers/menu/controller.rb',
    'lib/shoko/adapters/input/controllers/reader/lifecycle_runner.rb',
    'lib/shoko/application/unified_application.rb',
    'lib/shoko/application/workflows/menu/download_workflow.rb',
    'lib/shoko/application/workflows/menu/dictionary_workflow.rb',
  ].freeze

  it 'requires fatal external-input rescue branches to terminate or re-raise' do
    offenders = []

    FATAL_RESCUE_FILES.map { |path| File.join(root, path) }.each do |path|
      lines = File.readlines(path)
      lines.each_with_index do |line, index|
        next unless line.match?(/^\s*rescue\s+Shoko::FatalExternalInputError/)

        body = fatal_rescue_body_lines(lines, index)
        next if terminating_body?(body)

        offenders << "#{rel(path)}:#{index + 1}"
      end
    end

    expect(offenders).to eq([]),
                         "Fatal external-input rescue branches must terminate or re-raise:\n#{offenders.join("\n")}"
  end

  it 'forbids bare rescue assignment syntax across runtime code' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    offenders = files.select { |path| non_comment_content(path).match?(/\brescue\s*=>\s*\w+/) }

    expect(offenders).to eq([]), "Found bare rescue assignment patterns:\n#{offenders.map { |p| rel(p) }.join("\n")}"
  end

  it 'forbids inline rescue expressions across runtime code' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    offenders = []
    files.each do |path|
      File.readlines(path).each_with_index do |line, index|
        next unless line.include?(' rescue ')

        stripped = line.strip
        next if stripped.start_with?('#')
        next if stripped.start_with?('rescue')

        offenders << "#{rel(path)}:#{index + 1}"
      end
    end

    expect(offenders).to eq([]), "Found inline rescue expressions:\n#{offenders.join("\n")}"
  end

  it 'forbids is_a?(Proc) fallback probing in runtime source' do
    files = Dir[File.join(lib_root, '**', '*.rb')]
    pattern = /\bis_a\?\(Proc\)/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to eq([]),
                         "Proc type fallback probing is not allowed:\n#{offenders.map { |path| rel(path) }.join("\n")}"
  end

  it 'forbids || NullRuntimeConfig.instance fallback expressions in runtime code' do
    offenders = analyzer.implicit_null_runtime_config_offenders(lib_root:)
    expect(offenders).to eq([]), "Implicit NullRuntimeConfig fallback expressions are not allowed:\n#{offenders.join("\n")}"
  end

  it 'forbids optional ternary resolution branches that resolve identically' do
    offenders = analyzer.stale_optional_resolution_offenders(lib_root:)
    expect(offenders).to eq([]),
                         "Optional resolution scaffolding remains with identical branches:\n#{offenders.join("\n")}"
  end

  def broad_rescue_body_reraises?(lines, rescue_index)
    rescue_indent = lines[rescue_index][/^\s*/].size
    index = rescue_index + 1

    while index < lines.length
      line = lines[index]
      stripped = line.strip
      indent = line[/^\s*/].size

      break if !stripped.empty? && indent <= rescue_indent && stripped.match?(/^(rescue|else|ensure|end)\b/)
      return true if stripped.match?(/\Araise\b/)

      index += 1
    end

    false
  end

  def fatal_rescue_body_lines(lines, rescue_index)
    rescue_indent = lines[rescue_index][/^\s*/].size
    index = rescue_index + 1
    body = []

    while index < lines.length
      line = lines[index]
      stripped = line.strip
      indent = line[/^\s*/].size

      break if indent <= rescue_indent && stripped.match?(/^(rescue|ensure|end)\b/)

      body << stripped unless stripped.empty? || stripped.start_with?('#')
      index += 1
    end

    body
  end

  def terminating_body?(body_lines)
    body_lines.any? do |line|
      line.start_with?('raise') || line.include?('terminate(2)') || line.include?('cleanup_and_exit(2')
    end
  end
end
