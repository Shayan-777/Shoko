# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Reader::SelectionInteraction do
  let(:config_reader) { double('ConfigReader', dictionary_backend: :sqlite) }
  let(:dictionary_availability) { double('DictionaryAvailability', sqlite3_available?: true) }
  let(:reader_state_reader) { double('ReaderState', popup_menu: nil, selection: nil) }
  let(:reader_session_mutator) { double('ReaderMutator', update_reader: nil, clear_selection: nil) }
  let(:mouse_handler) { double('MouseHandler', reset: nil, selection_range: nil) }
  let(:rendered_content_reader) { double('RenderedContentReader', rendered_lines: []) }
  let(:coordinate_service) { double('CoordinateService') }
  let(:selection_service) { double('SelectionService') }
  let(:ui_component_factory) { double('UiComponentFactory') }
  let(:popup_position_service) { double('PopupPositionService') }
  let(:clipboard_service) { double('ClipboardService') }
  let(:popup_controller) do
    double(
      'PopupController',
      dictionary_visible?: false,
      annotation_editor_visible?: false,
      in_book_search_visible?: false,
      translator_visible?: false
    )
  end
  let(:draw) { instance_double(Proc, call: nil) }
  let(:switch_mode) { instance_double(Proc, call: nil) }
  let(:popup_action) { instance_double(Proc, call: nil) }

  subject(:interaction) do
    described_class.new(
      state: described_class::StateDependencies.new(
        reader_state_reader: reader_state_reader,
        reader_session_mutator: reader_session_mutator,
        rendered_content_reader: rendered_content_reader,
        config_reader: config_reader
      ),
      services: described_class::ServiceDependencies.new(
        coordinate_service: coordinate_service,
        selection_service: selection_service,
        mouse_handler: mouse_handler,
        dictionary_availability: dictionary_availability,
        ui_component_factory: ui_component_factory,
        popup_position_service: popup_position_service,
        clipboard_service: clipboard_service
      ),
      callbacks: described_class::Callbacks.new(
        ui_controller: ->(_request) { popup_controller },
        draw: draw,
        switch_mode: switch_mode,
        popup_action: popup_action
      )
    )
  end

  describe '#dictionary_available?' do
    it 'requires both the runtime capability and an enabled backend' do
      expect(interaction.dictionary_available?).to be(true)

      allow(config_reader).to receive(:dictionary_backend).and_return(:disabled)
      expect(interaction.dictionary_available?).to be(false)

      allow(config_reader).to receive(:dictionary_backend).and_return(:sqlite)
      allow(dictionary_availability).to receive(:sqlite3_available?).and_return(false)
      expect(interaction.dictionary_available?).to be(false)
    end
  end

  describe 'selection completion' do
    it 'keeps a non-empty selection without opening a popup' do
      selection = { start: {}, end: {} }
      allow(reader_state_reader).to receive(:selection).and_return(selection)
      allow(selection_service).to receive(:extract_text).with(selection, []).and_return('selected')

      expect(ui_component_factory).not_to receive(:enhanced_popup_menu)
      interaction.finish_selection
    end
  end

  describe 'right-click context routing' do
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
    let(:popup) { double('Popup', visible: true, handle_click: nil) }

    def anchor_at(cell_index)
      Shoko::Core::Models::SelectionAnchor.new(
        page_id: 0, column_id: 0, geometry_key: 'g1', line_offset: 0,
        cell_index: cell_index, row: 10, column_origin: 1
      )
    end

    before do
      allow(reader_state_reader).to receive(:selection).and_return(selection)
      allow(rendered_content_reader).to receive(:rendered_lines).and_return(rendered_lines)
      allow(selection_service).to receive(:extract_text).and_return('abc')
      allow(coordinate_service).to receive(:normalize_selection_range).and_return(selection)
      allow(coordinate_service).to receive(:mouse_to_terminal).and_return(x: 44, y: 16)
      allow(ui_component_factory).to receive(:enhanced_popup_menu).and_return(popup)
    end

    it 'opens only for a right-click inside the selected range' do
      click_anchor = anchor_at(4)
      allow(coordinate_service).to receive(:anchor_from_point).and_return(click_anchor)

      expect(interaction.context_click_handled?(button: 2, released: false, x: 43, y: 15)).to be(true)
      expect(reader_session_mutator).to have_received(:update_reader).with(
        popup_menu: popup, popup_menu_selected: 0
      )
      expect(switch_mode).to have_received(:call).with(:popup_menu)
    end

    it 'rejects a right-click outside the selected range' do
      outside = anchor_at(20)
      allow(coordinate_service).to receive(:anchor_from_point).and_return(outside)

      expect(interaction.context_click_handled?(button: 2, released: false, x: 43, y: 15)).to be(false)
      expect(ui_component_factory).not_to have_received(:enhanced_popup_menu)
    end

    it 'suppresses the release paired with the press that opened the popup' do
      allow(coordinate_service).to receive(:anchor_from_point).and_return(anchor_at(4))
      interaction.context_click_handled?(button: 2, released: false, x: 43, y: 15)
      allow(reader_state_reader).to receive(:popup_menu).and_return(popup)

      interaction.handle_overlay?(button: 2, released: true, x: 43, y: 15)

      expect(popup).not_to have_received(:handle_click)
    end
  end
end
