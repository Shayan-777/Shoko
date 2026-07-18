# frozen_string_literal: true

require 'spec_helper'

# Consolidated state-system rules (constitution §V): schema partition purity,
# state-store port discipline, scan-state ownership, canonical key reads, and
# the adapter-owned render/UI-component registries. Absorbs the former
# layered_state, state_store, catalog_scan_state, mixed-key, render_registry
# and reader_ui_registry suites.
RSpec.describe 'State conventions' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  def rel(path)
    path.delete_prefix("#{lib_root}/")
  end

  describe 'schema partition purity' do
    # Field-name shape predicates that indicate UI presentation. The domain
    # reading schema and the non-view application fragments must not grow
    # UI-shape fields; MenuProcess and UiGlobals are the designated hosts.
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

    def ui_shape_offenders_for(schema_module)
      schema_module::FIELDS.select do |field|
        UI_SHAPE_PATTERNS.any? { |pattern| pattern.match?(field.to_s) }
      end
    end

    it 'forbids UI-shape fields in Core::Reading::Schema (domain reading state)' do
      expect(ui_shape_offenders_for(Shoko::Core::Reading::Schema)).to eq([]),
                                                                     'Core reading schema must hold only domain reading state; ' \
                                                                     'UI-shape fields belong to a UI-designated fragment (ReaderView/UiGlobals).'
    end

    it 'forbids UI-shape fields in Application::State::Schema::ReaderProcess' do
      expect(ui_shape_offenders_for(Shoko::Application::State::Schema::ReaderProcess)).to eq([]),
                                                                                          'ReaderProcess is application process state; UI presentation ' \
                                                                                          'fields belong to ReaderView.'
    end

    it 'forbids UI-shape fields in Application::State::Schema::ReaderPagination' do
      expect(ui_shape_offenders_for(Shoko::Application::State::Schema::ReaderPagination)).to eq([]),
                                                                                             'ReaderPagination owns derived layout state; UI presentation ' \
                                                                                             'fields belong to ReaderView.'
    end

    it 'forbids UI-shape fields in Application::State::Schema::MenuTransient' do
      expect(ui_shape_offenders_for(Shoko::Application::State::Schema::MenuTransient)).to eq([]),
                                                                                          'MenuTransient holds workflow results; UI presentation ' \
                                                                                          'fields belong to MenuProcess.'
    end

    it 'forbids UI-shape fields in Application::State::Schema::Config' do
      expect(ui_shape_offenders_for(Shoko::Application::State::Schema::Config)).to eq([]),
                                                                                  'Config holds user preferences; UI presentation fields belong ' \
                                                                                  'to the view schema.'
    end
  end

  describe 'state-store port discipline' do
    it 'forbids direct filesystem probes in the application state store' do
      files = [
        File.join(lib_root, 'application', 'state', 'state_store.rb'),
        File.join(lib_root, 'application', 'state', 'observer_state_store.rb'),
        File.join(lib_root, 'application', 'state', 'config_persistence.rb'),
      ]
      offenders = files.filter_map do |path|
        next unless File.read(path).include?('File.exist?')

        rel(path)
      end

      expect(offenders).to be_empty,
                           "State stores must use config storage port instead of File.exist?:\n#{offenders.join("\n")}"
    end

    it 'requires state-store persistence collaborators to rely on config_storage.file_exist?' do
      files = [
        File.join(lib_root, 'application', 'state', 'observer_state_store.rb'),
        File.join(lib_root, 'application', 'state', 'config_persistence.rb'),
      ]
      missing = files.filter_map do |path|
        next if File.read(path).include?('file_exist?')

        rel(path)
      end

      expect(missing).to be_empty,
                         "State stores must delegate existence checks to config storage port:\n#{missing.join("\n")}"
    end
  end

  describe 'scan-state ownership' do
    it 'forbids direct scan_status/scan_message mutation outside catalog service' do
      files = Dir[File.join(lib_root, '**', '*.rb')]
      files -= [
        File.join(lib_root, 'application', 'use_cases', 'catalog_service.rb'),
        File.join(lib_root, 'adapters', 'book_sources', 'library_scanner.rb'),
      ]
      # Match assignment (=) but not comparison (==).
      pattern = /\bscan_(?:status|message)\s*=(?!=)/

      offenders = files.filter_map do |path|
        next unless File.read(path).match?(pattern)

        rel(path)
      end

      expect(offenders).to be_empty,
                           "Scan-state mutation must stay behind CatalogService API:\n#{offenders.sort.join("\n")}"
    end
  end

  describe 'canonical key reads' do
    MIXED_KEY_PATTERNS = [
      /\b([a-z_]\w*)\[:([a-z_]\w*)\]\s*\|\|\s*\1\[['"]\2['"]\]/i,
      /\b([a-z_]\w*)\[['"]([a-z_]\w*)['"]\]\s*\|\|\s*\1\[:\2\]/i,
      /\b([a-z_]\w*)\[(\w+)\]\s*\|\|\s*\1\[\2\.to_s\]/i,
      /\b([a-z_]\w*)\[(\w+)\.to_s\]\s*\|\|\s*\1\[\2\]/i,
    ].freeze

    it 'forbids mixed symbol/string fallback reads outside coercion boundaries' do
      offenders = Dir[File.join(lib_root, '**', '*.rb')].flat_map do |path|
        File.readlines(path).each_with_index.filter_map do |line, index|
          next if line.strip.start_with?('#')
          next unless MIXED_KEY_PATTERNS.any? { |pattern| line.match?(pattern) }

          "#{rel(path)}:#{index + 1}"
        end
      end

      expect(offenders).to eq([]),
                           "Canonical payloads must be consumed without mixed-key fallback reads:\n#{offenders.join("\n")}"
    end
  end

  describe 'render geometry stays adapter-owned' do
    it 'keeps rendered_lines out of the reader snapshot contract' do
      expect(Shoko::Application::Ports::Outbound::State::ReaderSnapshot::FIELDS).not_to include(:rendered_lines),
                                                                                        'ReaderSnapshot FIELDS must not expose rendered_lines once render geometry is adapter-owned'
    end

    it 'keeps rendered_lines out of layered schema fragments' do
      reader_view_schema_path = File.join(lib_root, 'application', 'state', 'schema', 'reader_view.rb')
      offenders = []
      offenders << 'reader_view_schema.rb' if non_comment_content(reader_view_schema_path).include?('rendered_lines:')

      expect(offenders).to eq([]),
                           "Rendered geometry must not live in layered schemas:\n#{offenders.join("\n")}"
    end

    it 'keeps the render registry the only rendered-lines channel' do
      rendered_content_reader_path = File.join(lib_root, 'adapters', 'runtime', 'session_state',
                                               'rendered_content_reader_adapter.rb')
      render_state_writer_path = File.join(lib_root, 'adapters', 'runtime', 'session_state',
                                           'render_state_writer_adapter.rb')

      reader_content = non_comment_content(rendered_content_reader_path)
      writer_content = non_comment_content(render_state_writer_path)

      expect(reader_content).not_to include('ReaderSelectors.rendered_lines'),
                                    'RenderedContentReaderAdapter must read from the render registry directly'
      expect(reader_content).not_to include('%i[reader rendered_lines]'),
                                    'RenderedContentReaderAdapter must not fall back to reader state'
      expect(writer_content).not_to include('dispatch('),
                                    'RenderStateWriterAdapter must not publish render geometry into the state store'
    end
  end

  describe 'live UI components stay out of state' do
    let(:forbidden_component_fields) do
      %i[
        popup_menu
        in_book_search_popup
        annotations_overlay
        annotation_editor_overlay
        translation_popup
        dictionary_popup
        dictionary_panel
      ]
    end

    it 'keeps live UI component fields out of every layered reader snapshot contract' do
      offenders = forbidden_component_fields.flat_map do |field|
        types = {
          ReaderSessionSnapshot: Shoko::Application::Ports::Outbound::State::ReaderSessionSnapshot,
          ReaderViewSnapshot: Shoko::Application::Ports::Outbound::State::ReaderViewSnapshot,
          ReaderPaginationSnapshot: Shoko::Application::Ports::Outbound::State::ReaderPaginationSnapshot,
          ReaderSnapshot: Shoko::Application::Ports::Outbound::State::ReaderSnapshot,
        }
        types.filter_map { |name, klass| "#{name}:#{field}" if klass::FIELDS.include?(field) }
      end

      expect(offenders).to eq([]),
                           "Live UI component fields must not appear in reader snapshot contracts: #{offenders.join(', ')}"
    end

    it 'keeps live UI component fields out of layered schema fragments' do
      schema_content = non_comment_content(File.join(lib_root, 'application', 'state', 'schema', 'reader_view.rb'))

      offenders = forbidden_component_fields.each_with_object([]) do |field, values|
        values << "reader_view_schema:#{field}" if schema_content.match?(/\b#{Regexp.escape(field.to_s)}\s*:/)
      end

      expect(offenders).to eq([]),
                           "Live UI component fields must not be reintroduced into schemas:\n#{offenders.join("\n")}"
    end

    it 'requires the UI-owned component registry for live UI objects' do
      registry_path = File.join(lib_root, 'adapters', 'ui', 'state', 'reader_component_registry.rb')

      expect(File.exist?(registry_path)).to be(true),
                                            "Reader UI component registry must exist for live UI objects: #{registry_path}"
    end
  end

  describe 'frozen-tree state invariant' do
    def build_store(dir, registry: nil)
      storage = Object.new
      file = File.join(dir, 'config.json')
      storage.define_singleton_method(:config_dir) { dir }
      storage.define_singleton_method(:config_file) { file }
      storage.define_singleton_method(:ensure_config_dir) { FileUtils.mkdir_p(dir) }
      storage.define_singleton_method(:atomic_write) { |path, data| File.write(path, data) }
      storage.define_singleton_method(:read_file) { |path| File.exist?(path) ? File.read(path) : nil }
      storage.define_singleton_method(:file_exist?) { |path| File.exist?(path) }

      registry ||= Shoko::Application::State::SchemaRegistry.new
                                                            .register(Shoko::Core::Reading::Schema)
                                                            .register(Shoko::Application::State::Schema::ReaderProcess)
                                                            .register(Shoko::Application::State::Schema::ReaderPagination)
                                                            .register(Shoko::Application::State::Schema::ReaderView)
                                                            .register(Shoko::Application::State::Schema::MenuProcess)
                                                            .register(Shoko::Application::State::Schema::MenuTransient)
                                                            .register(Shoko::Application::State::Schema::Config)
                                                            .register(Shoko::Application::State::Schema::UiGlobals)

      Shoko::Application::State::StateStore.new(
        config_storage: storage,
        terminal_capabilities: Shoko::Adapters::Output::Terminal::NullTerminalCapabilities.new,
        schema_registry: registry
      )
    end

    # Walks every node of a state tree: containers, Struct/Data members,
    # and opaque leaves alike, yielding [node, kind].
    def each_state_node(node, &block)
      case node
      when Hash
        yield node, :container
        node.each do |key, child|
          each_state_node(key, &block)
          each_state_node(child, &block)
        end
      when Array
        yield node, :container
        node.each { |child| each_state_node(child, &block) }
      when String, Struct
        yield node, :container
        node.each { |child| each_state_node(child, &block) } if node.is_a?(Struct)
      when Data
        yield node, :container
        Data.instance_method(:to_h).bind_call(node).each_value { |child| each_state_node(child, &block) }
      else
        if Shoko::Shared::DeepStructure::IMMUTABLE_PRIMITIVE_CLASSES.include?(node.class)
          nil
        else
          yield node, :opaque_leaf
        end
      end
    end

    def each_data_node(node, &block)
      each_state_node(node) { |n, kind| block.call(n) if kind == :container }
    end

    it 'keeps every container frozen and every leaf inside the closed value contract' do
      Dir.mktmpdir do |dir|
        store = build_store(dir)
        each_data_node(store.peek) { |node| expect(node).to be_frozen }
        opaque = []
        each_state_node(store.peek) { |node, kind| opaque << node if kind == :opaque_leaf }
        expect(opaque).to eq([])

        store.update(%i[reader bookmarks] => [{ chapter: 1 }], %i[ui terminal_width] => 120)
        each_data_node(store.peek) { |node| expect(node).to be_frozen }
      end
    end

    it 'deep-freezes Struct and Data leaves so mutable value objects cannot bypass the write path' do
      Dir.mktmpdir do |dir|
        store = build_store(dir)
        match = Shoko::Core::Services::InBookSearchService::SearchMatch.new(0, 'Title', 1, 'before', 'match', 'after')

        store.update(%i[ui search_results] => [match])

        stored = store.peek_at(:ui, :search_results).first
        expect(stored).not_to equal(match), 'inserted Structs must be copied, not shared'
        expect(stored).to be_frozen
        expect(stored.before).to be_frozen
        expect { stored.match = 'sneak' }.to raise_error(FrozenError)
        expect(match).not_to be_frozen, 'callers keep ownership of their Struct arguments'

        # Mutating the caller-side original must not reach stored state.
        match.match = 'mutated outside store'
        expect(store.peek_at(:ui, :search_results).first.match).to eq('match')
      end
    end

    it 'rejects all opaque leaves even when the outer object is frozen' do
      Dir.mktmpdir do |dir|
        store = build_store(dir)
        reader_only_wrapper = Class.new do
          attr_reader :items

          def initialize = @items = []
        end.new.freeze

        expect { store.update(%i[ui search_results] => [reader_only_wrapper]) }
          .to raise_error(Shoko::Shared::DeepStructure::InadmissibleValueError, /not admissible/)
      end
    end

    it 'admits dictionary Data values without sharing their constructor arguments' do
      Dir.mktmpdir do |dir|
        store = build_store(dir)
        caller_entries = [Shoko::Core::Models::DictionaryEntry.new(word: 'w', senses: ['s'])]
        result = Shoko::Core::Models::DictionaryResult.new(
          query: 'q',
          entries: caller_entries
        )

        store.update(%i[menu dictionary_results] => [result])

        stored = store.peek_at(:menu, :dictionary_results).first
        expect(stored).to be_a(Shoko::Core::Models::DictionaryResult)
        expect(stored).not_to equal(result)
        expect(stored.entries).to be_frozen
        expect(stored.entries.first.senses.first).to be_frozen
        expect(caller_entries).not_to be_frozen
      end
    end

    it 'rejects mutable Numeric subclasses instead of treating Numeric as intrinsically immutable' do
      Dir.mktmpdir do |dir|
        store = build_store(dir)
        mutable_numeric = Class.new(Numeric) do
          attr_reader :items

          def initialize = @items = []
        end.new

        expect { store.update(%i[ui search_results] => [mutable_numeric]) }
          .to raise_error(Shoko::Shared::DeepStructure::InadmissibleValueError, /opaque objects/)
      end
    end

    it 'uses declared Data members rather than an overridden serialization to_h' do
      Dir.mktmpdir do |dir|
        store = build_store(dir)
        timestamp = +'2026-07-18T00:00:00Z'
        progress = Shoko::Core::Models::ReadingProgress.new(
          chapter_index: 3, line_offset: 9, timestamp: timestamp
        )

        store.update(%i[ui search_results] => [progress])

        stored = store.peek_at(:ui, :search_results).first
        expect(stored.chapter_index).to eq(3)
        expect(stored.timestamp).to eq(timestamp)
        expect(stored.timestamp).to be_frozen
        expect(timestamp).not_to be_frozen
      end
    end

    it 'rejects cycles and Hashes whose lookup semantics cannot be preserved as plain state data' do
      Dir.mktmpdir do |dir|
        store = build_store(dir)
        cyclic = []
        cyclic << cyclic
        defaulted = Hash.new { |_hash, key| key }

        expect { store.update(%i[ui search_results] => cyclic) }
          .to raise_error(Shoko::Shared::DeepStructure::InadmissibleValueError, /cyclic/)
        expect { store.update(%i[ui search_results] => defaulted) }
          .to raise_error(Shoko::Shared::DeepStructure::InadmissibleValueError, /nil defaults/)
      end
    end

    it 'rejects hidden instance state and singleton behavior on otherwise plain containers' do
      Dir.mktmpdir do |dir|
        store = build_store(dir)
        adorned_array = []
        adorned_array.instance_variable_set(:@hidden, [])
        adorned_string = +'visible'
        adorned_string.define_singleton_method(:hidden) { [] }

        expect { store.update(%i[ui search_results] => adorned_array) }
          .to raise_error(Shoko::Shared::DeepStructure::InadmissibleValueError, /declared elements/)
        expect { store.update(%i[ui search_results] => adorned_string) }
          .to raise_error(Shoko::Shared::DeepStructure::InadmissibleValueError, /declared elements/)
      end
    end

    it 'applies the same admission contract to schema-provided initial state' do
      Dir.mktmpdir do |dir|
        mutable = Object.new
        fragment = Module.new do
          define_singleton_method(:contribute) { |_context| { ui: { injected: mutable } } }
        end
        registry = Shoko::Application::State::SchemaRegistry.new.register(fragment)

        expect { build_store(dir, registry: registry) }
          .to raise_error(Shoko::Shared::DeepStructure::InadmissibleValueError, /Object/)
      end
    end

    it 'keeps caller ownership for inserted Data values (members are copied, not frozen in place)' do
      Dir.mktmpdir do |dir|
        store = build_store(dir)
        data_class = Data.define(:items)
        mine = data_class.new(items: [1, 2])

        store.update(%i[ui search_results] => [mine])

        stored = store.peek_at(:ui, :search_results).first
        expect(stored).not_to equal(mine)
        expect(stored).to be_frozen
        expect(stored.items).to be_frozen
        expect(mine.items).not_to be_frozen, 'the caller keeps a mutable copy of their own members'
      end
    end

    it 'raises on out-of-band mutation instead of bypassing the write path' do
      Dir.mktmpdir do |dir|
        store = build_store(dir)

        expect { store.peek[:reader][:bookmarks] << :sneak }.to raise_error(FrozenError)
        expect { store.peek[:reader][:current_chapter] = 9 }.to raise_error(FrozenError)
      end
    end

    it 'deep-dups inserted values so callers keep ownership of their arguments' do
      Dir.mktmpdir do |dir|
        store = build_store(dir)
        mine = [{ chapter: 2 }]

        store.update(%i[reader bookmarks] => mine)

        expect(mine).not_to be_frozen
        stored = store.peek_at(:reader, :bookmarks)
        expect(stored).to be_frozen
        expect(stored).not_to equal(mine)
      end
    end

    it 'shares no mutable structure between independently built stores' do
      Dir.mktmpdir do |dir_a|
        Dir.mktmpdir do |dir_b|
          store_a = build_store(dir_a)
          store_b = build_store(dir_b)

          shared_mutable = []
          seen = {}.compare_by_identity
          each_data_node(store_a.peek) { |node| seen[node] = true }
          each_data_node(store_b.peek) do |node|
            shared_mutable << node if seen.key?(node) && !node.frozen?
          end

          expect(shared_mutable).to eq([])
        end
      end
    end

    it 'keeps schema fragment defaults deep-frozen' do
      fragments = [
        Shoko::Core::Reading::Schema,
        Shoko::Application::State::Schema::ReaderProcess,
        Shoko::Application::State::Schema::ReaderPagination,
        Shoko::Application::State::Schema::ReaderView,
        Shoko::Application::State::Schema::MenuProcess,
        Shoko::Application::State::Schema::MenuTransient,
        Shoko::Application::State::Schema::UiGlobals,
      ]

      fragments.each do |fragment|
        each_data_node(fragment::DEFAULTS) do |node|
          expect(node).to be_frozen, "#{fragment}::DEFAULTS holds an unfrozen #{node.class}"
        end
      end
    end
  end
end
