# frozen_string_literal: true

require 'spec_helper'

# Guardrails that protect the layered-state refactor (severity #1 of the
# 2026-05-26 audit) and the audit items handled alongside it. Each rule
# corresponds to a violation that was just resolved and that would
# silently regress without a structural test.
#
# Future-work items not yet eligible to be live are listed in PENDING_NOTES
# and registered via RSpec `it` ... `skip` so they remain visible.
#
# Categories:
#
# 1. Forbidden legacy constants  — anything that was relocated must not
#    return under its old name.
# 2. Forbidden legacy files      — relocated files must not reappear at
#    their old path.
# 3. UI-shape allow-deny lists   — domain reading schema and the
#    application non-view schema fragments must not grow UI presentation
#    fields. This is the structural cure for audit A4.
# 4. I/O leak bans               — `File.*` / `IO.*` must not appear in
#    `application/` or `shared/` (audit A3 + shared-purity).
# 5. Cross-layer surface         — DisplayLine must not live in core
#    (audit A2); `*_support.rb` is being removed directory-by-directory
#    and the live set is tracked here as it expands.
RSpec.describe 'Layered state guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:all_lib_files) { Dir[File.join(lib_root, '**', '*.rb')] }
  let(:application_files) { Dir[File.join(lib_root, 'application', '**', '*.rb')] }
  let(:shared_files) { Dir[File.join(lib_root, 'shared', '**', '*.rb')] }
  let(:core_files) { Dir[File.join(lib_root, 'core', '**', '*.rb')] }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue Errno::ENOENT
    ''
  end

  def rel(path)
    path.delete_prefix("#{lib_root}/")
  end

  # ─── 1. Forbidden legacy constants ───────────────────────────────────

  describe 'forbidden legacy constants' do
    # The state store, observer store, event bus, and UI session registry
    # were relocated. References to the old constants must not return.
    forbidden = {
      'Adapters::Runtime::SessionState::StateStore' =>
        /\bShoko::Adapters::Runtime::SessionState::StateStore\b/,
      'Adapters::Runtime::SessionState::ObserverStateStore' =>
        /\bShoko::Adapters::Runtime::SessionState::ObserverStateStore\b/,
      'Adapters::Runtime::SessionState::EventBus' =>
        /\bShoko::Adapters::Runtime::SessionState::EventBus\b/,
      'Adapters::Runtime::SessionState::ReaderUiSessionRegistry' =>
        /\bShoko::Adapters::Runtime::SessionState::ReaderUiSessionRegistry\b/,
      'Core::Models::Session' => /\bShoko::Core::Models::Session\b/,
      'Shared::MenuDefinitions' => /\bShoko::Shared::MenuDefinitions\b/,
    }

    forbidden.each do |label, pattern|
      it "forbids #{label} from reappearing" do
        offenders = all_lib_files.select { |path| non_comment_content(path).match?(pattern) }

        expect(offenders).to be_empty,
                             "Legacy constant #{label} reappeared in:\n#{offenders.map { |p| rel(p) }.join("\n")}"
      end
    end
  end

  # ─── 2. Forbidden legacy files ──────────────────────────────────────

  describe 'forbidden legacy files' do
    legacy_paths = [
      'adapters/runtime/session_state/state_store.rb',
      'adapters/runtime/session_state/observer_state_store.rb',
      'adapters/runtime/session_state/event_bus.rb',
      'adapters/runtime/session_state/reader_ui_session_registry.rb',
      'adapters/runtime/session_state/state_store',
      'core/models/session',
      'shared/menu_definitions.rb',
    ]

    legacy_paths.each do |relative_path|
      it "keeps #{relative_path} from being recreated" do
        full_path = File.join(lib_root, relative_path)
        expect(File.exist?(full_path)).to be(false),
                                          "Legacy path must stay removed: lib/shoko/#{relative_path}"
      end
    end
  end

  # ─── 3. UI-shape allow-deny lists ───────────────────────────────────

  describe 'UI-shape allow-deny on layer schemas' do
    # Field-name shape predicates that indicate UI presentation. If any
    # of these fragments grow such a field, A4 is regressing.
    UI_SHAPE_PATTERNS = [
      /\Asidebar_/,
      /\Apopup/,
      /_popup\z/,
      /dictionary_visible\z/,
      /\Ahovered_/,
      /\Aterminal_(width|height)\z/,
      /_cursor\z/,
      /_scroll\z/,
      /_zen_mode\z/,
      /_focus\z/,
      /search_landing_highlight/,
    ].freeze

    def offenders_for(schema_module)
      schema_module::FIELDS.select do |field|
        UI_SHAPE_PATTERNS.any? { |pattern| pattern.match?(field.to_s) }
      end
    end

    it 'forbids UI-shape fields in Core::Reading::Schema (domain reading state)' do
      expect(offenders_for(Shoko::Core::Reading::Schema)).to eq([]),
                                                             'Core reading schema must hold only domain reading state; ' \
                                                             'UI-shape fields belong to a UI-owned schema fragment.'
    end

    it 'forbids UI-shape fields in Application::State::Schema::ReaderProcess' do
      expect(offenders_for(Shoko::Application::State::Schema::ReaderProcess)).to eq([]),
                                                                                  'ReaderProcess is application process state; UI presentation ' \
                                                                                  'fields belong to ReaderView (or the future UI-owned schema).'
    end

    it 'forbids UI-shape fields in Application::State::Schema::ReaderPagination' do
      expect(offenders_for(Shoko::Application::State::Schema::ReaderPagination)).to eq([]),
                                                                                     'ReaderPagination owns derived layout state; UI presentation ' \
                                                                                     'fields belong to ReaderView.'
    end

    it 'forbids UI-shape fields in Application::State::Schema::MenuTransient' do
      expect(offenders_for(Shoko::Application::State::Schema::MenuTransient)).to eq([]),
                                                                                  'MenuTransient holds workflow results; UI presentation ' \
                                                                                  'fields belong to MenuProcess (currently) or the future UI-owned schema.'
    end

    it 'forbids UI-shape fields in Application::State::Schema::Config' do
      expect(offenders_for(Shoko::Application::State::Schema::Config)).to eq([]),
                                                                          'Config holds user preferences; UI presentation fields belong ' \
                                                                          'to the view schema.'
    end

    # MenuProcess and UiGlobals legitimately host UI-shape fields under
    # the Option-A compromise documented in their modules. They are
    # excluded here intentionally; Option B will move those fields to a
    # UI-owned schema and this exclusion will go away.
  end

  # ─── 4. I/O leak bans ───────────────────────────────────────────────

  describe 'I/O leak bans' do
    # All previously-exempt application files have been cleaned. Keep
    # the constant in place as the seam for future audited exemptions;
    # the default position is zero tolerance.
    EXEMPT_APPLICATION_FILES = [].freeze

    it 'forbids File.* / IO.* in lib/shoko/application/ (modulo audited exemptions)' do
      pattern = /\b(?:File|IO)\.[A-Za-z_]/
      offenders = application_files.filter_map do |path|
        next unless non_comment_content(path).match?(pattern)

        rel(path)
      end - EXEMPT_APPLICATION_FILES

      expect(offenders).to be_empty,
                           "Application layer must use ports for I/O; offenders:\n#{offenders.sort.join("\n")}"
    end

    # The shared layer is permitted to load its OWN bundled data files
    # (unicode tables, codepoint maps) and to provide pure utilities that
    # take a path/IO argument and return a value (hashing, gem probing).
    # It must not derive application semantics from the filesystem. The
    # exempt list below is the audited, pre-existing legitimate use; if
    # a new shared file needs File/IO access, it almost certainly belongs
    # in an adapter, not shared.
    EXEMPT_SHARED_FILES = [
      'shared/optional_dependency.rb',               # gem-load probing
      'shared/source_fingerprint.rb',                # SHA over an input path
      'shared/terminal/kitty_unicode_placeholders.rb', # bundled codepoint table
      'shared/unicode_display_width.rb',             # bundled width table
    ].freeze

    it 'forbids File.* / IO.* in lib/shoko/shared/ (modulo audited exemptions)' do
      pattern = /\b(?:File|IO)\.[A-Za-z_]/
      offenders = shared_files.filter_map do |path|
        next unless non_comment_content(path).match?(pattern)

        rel(path)
      end - EXEMPT_SHARED_FILES

      expect(offenders).to be_empty,
                           "Shared layer is a pure-utility leaf; offenders:\n#{offenders.sort.join("\n")}"
    end
  end

  # ─── 5. Cross-layer surface ─────────────────────────────────────────

  describe 'cross-layer type surface' do
    it 'keeps DisplayLine out of core (Core::Models::DisplayLine must not be defined)' do
      core_models = Shoko::Core::Models
      offender = core_models.constants(false).find { |name| name == :DisplayLine }

      expect(offender).to be_nil,
                          'DisplayLine is a renderer type and must not live in Core::Models. ' \
                          'Its canonical home is Application::Ports::Outbound::Formatting::DisplayLine.'
    end

    it 'forbids any DisplayLine constant reference inside core/' do
      core_const_match = core_files.select do |path|
        non_comment_content(path).match?(/\bDisplayLine\b/)
      end

      expect(core_const_match).to eq([]),
                                  "Core files referencing DisplayLine (use String-vs-other duck pattern instead):\n" \
                                  "#{core_const_match.map { |p| rel(p) }.join("\n")}"
    end
  end

  describe '*_support.rb deprecation' do
    # The `*_support.rb` mixin pattern is being eliminated directory by
    # directory. As each directory is cleaned, add it to LIVE_DIRECTORIES;
    # the directories in DEFERRED_DIRECTORIES are pending future sessions
    # and tracked here so the work isn't forgotten.
    LIVE_DIRECTORIES = [
      # Step 4 of the layered-state refactor: bookmark_service/navigation_support.rb
      # was folded back into BookmarkService. The host class absorbed all 14
      # methods; no external consumer of the mixin existed. The pattern of
      # extracting "navigation/page-resolution helpers" into a *_support
      # mixin solely to keep the host file smaller is now banned for this
      # directory. Other directories follow as future sessions clean them.
      'application/services/reader/bookmark_service',
    ].freeze

    DEFERRED_DIRECTORIES = [
      'application/state',
      'application/services',
      'application/use_cases',
      'application/workflows',
      'adapters/runtime/session_state',
      'adapters/input/controllers',
      'adapters/input/reader_input_controller',
      'adapters/storage',
      'adapters/storage/cache/epub',
      'adapters/storage/json_cache_store',
      'adapters/storage/sqlite_dictionary_adapter',
      'adapters/storage/repositories',
      'adapters/output/formatting',
      'adapters/output/formatting/formatting_service',
      'adapters/output/formatting/formatting_service/line_assembler',
      'adapters/output/formatting/formatting_service/line_assembler/table_renderer',
      'adapters/output/terminal',
      'adapters/output/terminal/input',
      'adapters/book_sources/epub',
      'adapters/book_sources/epub/epub_importer',
      'adapters/book_sources/epub/parser/xhtml_content_parser',
      'adapters/book_sources/fb2/fb2_importer',
      'adapters/book_sources/kindle/kindle_importer',
      'adapters/book_sources/pdf/parser',
      'adapters/book_sources/pdf/importer',
      'adapters/book_sources/rtf/rtf_importer',
      'adapters/book_sources/libgen_client',
      'adapters/book_sources/book_finder',
      'adapters/rss/rss_reader_service',
      'adapters/translation',
      'adapters/ui/components',
      'adapters/ui/sessions',
      'adapters/ui/sessions/annotation_overlay_ui_session',
      'adapters/ui/sessions/dictionary_ui_session',
      'adapters/ui/components/sidebar/toc',
      'adapters/ui/components/screens',
      'adapters/ui/components/screens/settings_screen_component',
      'adapters/ui/components/screens/dictionary_settings_screen_component',
      'core/services',
      'core/services/dictionary_service',
      'core/services/in_book_search_service',
      'shared/terminal',
    ].freeze

    LIVE_DIRECTORIES.each do |dir|
      it "has zero *_support.rb files under #{dir}" do
        offenders = Dir[File.join(lib_root, dir, '*_support.rb')]
        expect(offenders).to eq([]),
                             "Cleaned directory regressed:\n#{offenders.map { |p| rel(p) }.join("\n")}"
      end
    end

    DEFERRED_DIRECTORIES.each do |dir|
      it "(pending) will forbid *_support.rb under #{dir}" do
        skip "Deferred to a future session. Currently has #{Dir[File.join(lib_root, dir, '*_support.rb')].length} *_support.rb files."
      end
    end
  end
end
