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
end
