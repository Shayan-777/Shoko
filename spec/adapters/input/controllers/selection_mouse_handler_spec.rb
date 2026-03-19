# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::SelectionMouseHandler do
  let(:handler_class) do
    Class.new do
      include Shoko::Adapters::Input::Controllers::SelectionMouseHandler

      def initialize(config_reader, dict_avail)
        @config_reader = config_reader
        @dictionary_availability = dict_avail
      end
    end
  end
  let(:config_reader_class) do
    Class.new do
      def initialize(backend)
        @backend = backend
      end

      def dictionary_backend
        @backend
      end

      def dictionary_path
        nil
      end
    end
  end
  let(:dict_availability_class) do
    Class.new do
      def initialize(sqlite3_available:, databases_present: false, env_override_enabled: false)
        @sqlite3_available = sqlite3_available
        @databases_present = databases_present
        @env_override_enabled = env_override_enabled
      end

      def sqlite3_available?
        @sqlite3_available
      end

      def databases_present?(_path)
        @databases_present
      end

      def env_override_enabled?
        @env_override_enabled
      end
    end
  end
  let(:dict_avail) { dict_availability_class.new(sqlite3_available: true, databases_present: false) }
  let(:handler) { handler_class.new(config_reader, dict_avail) }

  describe '#dictionary_lookup_available?' do
    context 'when dictionary backend is disabled' do
      let(:config_reader) { config_reader_class.new(:disabled) }

      it 'returns false even if sqlite3 is installed' do
        expect(handler.send(:dictionary_lookup_available?)).to be(false)
      end
    end

    context 'when dictionary backend is auto and no databases are present' do
      let(:config_reader) { config_reader_class.new(nil) }

      it 'returns true when sqlite3 is installed' do
        expect(handler.send(:dictionary_lookup_available?)).to be(true)
      end
    end

    context 'when dictionary backend is auto and databases are present' do
      let(:config_reader) { config_reader_class.new(nil) }
      let(:dict_avail) { dict_availability_class.new(sqlite3_available: true, databases_present: true) }

      it 'returns true when sqlite3 is available' do
        expect(handler.send(:dictionary_lookup_available?)).to be(true)
      end
    end

    context 'when dictionary backend is enabled' do
      let(:config_reader) { config_reader_class.new(:sqlite) }

      it 'returns true when sqlite3 is available' do
        expect(handler.send(:dictionary_lookup_available?)).to be(true)
      end

      it 'returns false when sqlite3 is missing' do
        let_dict = dict_availability_class.new(sqlite3_available: false)
        h = handler_class.new(config_reader, let_dict)

        expect(h.send(:dictionary_lookup_available?)).to be(false)
      end
    end

    context 'when enabled via environment variable override' do
      let(:config_reader) { config_reader_class.new(nil) }
      let(:dict_avail) { dict_availability_class.new(sqlite3_available: true, env_override_enabled: true) }

      it 'returns true when sqlite3 is available' do
        expect(handler.send(:dictionary_lookup_available?)).to be(true)
      end
    end

    context 'when dictionary availability raises a typed dependency error' do
      let(:config_reader) { config_reader_class.new(:sqlite) }
      let(:dict_avail) { instance_double('DictionaryAvailability') }

      it 'returns false instead of crashing the UI path' do
        allow(dict_avail).to receive(:sqlite3_available?).and_raise(
          Shoko::DependencyUnavailableError,
          "Required optional gem 'sqlite3' is not installed"
        )

        expect(handler.send(:dictionary_lookup_available?)).to be(false)
      end
    end
  end

  describe '#handle_selection_end' do
    let(:config_reader) { config_reader_class.new(:sqlite) }

    it 'does not open popup immediately for a non-empty selection' do
      mouse_handler = instance_double('MouseHandler', selection_range: { start: { x: 1, y: 1 }, end: { x: 4, y: 1 } })
      reader_state = instance_double('ReaderStateReader', selection: { start: {}, end: {} })

      handler.instance_variable_set(:@mouse_handler, mouse_handler)
      handler.instance_variable_set(:@reader_state_reader, reader_state)

      allow(handler).to receive(:update_state_selection)
      allow(handler).to receive(:extract_selected_text).and_return('selected')
      expect(handler).not_to receive(:open_popup_menu)

      handler.send(:handle_selection_end)
    end
  end

  describe '#popup_context_click_handled?' do
    let(:config_reader) { config_reader_class.new(:sqlite) }
    let(:rendered_lines) { { 'g1' => { geometry: Object.new } } }
    let(:start_anchor) do
      Shoko::Core::Models::SelectionAnchor.new(
        page_id: 0, column_id: 0, geometry_key: 'g1', line_offset: 0, cell_index: 2, row: 10, column_origin: 1
      )
    end
    let(:end_anchor) do
      Shoko::Core::Models::SelectionAnchor.new(
        page_id: 0, column_id: 0, geometry_key: 'g1', line_offset: 0, cell_index: 7, row: 10, column_origin: 1
      )
    end
    let(:selection) { { start: start_anchor.to_h, end: end_anchor.to_h } }

    before do
      handler.instance_variable_set(:@selected_text, 'abc')
      handler.instance_variable_set(:@reader_state_reader, instance_double('ReaderStateReader', selection: selection))
      handler.instance_variable_set(
        :@rendered_content_reader,
        instance_double('RenderedContentReader', rendered_lines: rendered_lines)
      )
    end

    it 'opens popup only on right-click press inside selected range and anchors to click position' do
      click_anchor = Shoko::Core::Models::SelectionAnchor.new(
        page_id: 0, column_id: 0, geometry_key: 'g1', line_offset: 0, cell_index: 4, row: 10, column_origin: 1
      )
      coordinate_service = instance_double(
        'CoordinateService',
        anchor_from_point: click_anchor,
        normalize_selection_range: selection,
        mouse_to_terminal: { x: 44, y: 16 }
      )
      handler.instance_variable_set(:@coordinate_service, coordinate_service)

      expect(handler).to receive(:open_popup_menu).with(anchor_position: { x: 44, y: 16 }).and_return(true)
      result = handler.send(:popup_context_click_handled?, { button: 2, released: false, x: 43, y: 15 })

      expect(result).to be(true)
      expect(handler.instance_variable_get(:@suppress_popup_release_once)).to be(true)
    end

    it 'does not open popup when right-click is outside selected range' do
      outside_anchor = Shoko::Core::Models::SelectionAnchor.new(
        page_id: 0, column_id: 0, geometry_key: 'g1', line_offset: 0, cell_index: 20, row: 10, column_origin: 1
      )
      coordinate_service = instance_double(
        'CoordinateService',
        anchor_from_point: outside_anchor,
        normalize_selection_range: selection
      )
      handler.instance_variable_set(:@coordinate_service, coordinate_service)

      expect(handler).not_to receive(:open_popup_menu)
      result = handler.send(:popup_context_click_handled?, { button: 2, released: false, x: 43, y: 15 })

      expect(result).to be(false)
    end
  end
end
