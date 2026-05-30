# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::EnhancedPopupMenu do
  let(:selection_range) do
    {
      start: { page_id: 0, geometry_key: nil, line_offset: 0, cell_index: 0, row: 0, column_origin: 0 },
      end: { page_id: 0, geometry_key: nil, line_offset: 0, cell_index: 0, row: 0, column_origin: 0 },
    }
  end

  let(:coordinate_service) do
    instance_double('CoordinateService',
                    normalize_selection_range: selection_range,
                    within_bounds?: true)
  end
  let(:popup_position_service) { instance_double('PopupPositionService', calculate_popup_position: { x: 1, y: 1 }) }

  let(:clipboard_service) { instance_double('ClipboardService', available?: clipboard_available) }
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 120, height: 20) }

  # Fake observable reader view-state: the popup menu reads its selection cursor
  # from `popup_menu_selected` and writes changes back via `update_reader`.
  let(:popup_view_state) do
    fake = Object.new
    selected = 0
    fake.define_singleton_method(:popup_menu_selected) { selected }
    fake.define_singleton_method(:update_reader) do |attrs|
      selected = attrs[:popup_menu_selected] if attrs.key?(:popup_menu_selected)
    end
    fake
  end

  def build_menu(rendered_lines: {}, dictionary_enabled: false, anchor_position: nil, available_actions: nil)
    described_class.new(
      selection_range,
      available_actions: available_actions,
      coordinate_service: coordinate_service,
      reader_state_reader: popup_view_state,
      reader_session_mutator: popup_view_state,
      popup_position_service: popup_position_service,
      clipboard_service: clipboard_service,
      rendered_lines: rendered_lines,
      dictionary_enabled: dictionary_enabled,
      anchor_position: anchor_position
    )
  end

  describe 'default actions' do
    let(:clipboard_available) { false }

    it 'omits lookup when dictionary is disabled' do
      menu = build_menu(dictionary_enabled: false)
      labels = menu.instance_variable_get(:@available_actions).map { |action| action[:label] }

      expect(labels).to include('Create Annotation')
      expect(labels).not_to include('Look Up')
    end

    it 'includes lookup when dictionary is enabled' do
      menu = build_menu(dictionary_enabled: true)
      labels = menu.instance_variable_get(:@available_actions).map { |action| action[:label] }

      expect(labels).to include('Look Up')
      expect(labels).to include('Translate')
    end

    it 'includes clipboard action when available' do
      allow(clipboard_service).to receive(:available?).and_return(true)
      menu = build_menu(dictionary_enabled: false)
      labels = menu.instance_variable_get(:@available_actions).map { |action| action[:label] }

      expect(labels).to include('Copy to Clipboard')
      expect(labels).to include('Translate')
    end
  end

  describe '#handle_hover' do
    let(:clipboard_available) { true }

    it 'updates selected item when hovering over another row' do
      menu = build_menu(dictionary_enabled: true)

      expect(menu.selected_index).to eq(0)
      result = menu.handle_hover(menu.x + 1, menu.y + 2)

      expect(result).to eq(type: :selection_change)
      expect(menu.selected_index).to eq(1)
    end

    it 'does not change selection when hover stays on same row' do
      menu = build_menu(dictionary_enabled: true)

      result = menu.handle_hover(menu.x + 1, menu.y + 1)

      expect(result).to be_nil
      expect(menu.selected_index).to eq(0)
    end
  end

  describe 'positioning' do
    let(:clipboard_available) { false }

    it 'uses explicit anchor position when provided' do
      expect(popup_position_service).to receive(:calculate_popup_position)
        .with({ x: 42, y: 9 }, kind_of(Integer), kind_of(Integer))
        .and_return({ x: 77, y: 13 })

      menu = build_menu(dictionary_enabled: false, anchor_position: { x: 42, y: 9 })

      expect(menu.x).to eq(77)
      expect(menu.y).to eq(13)
    end
  end

  describe 'glass rendering' do
    let(:clipboard_available) { false }
    let(:row_text) { 'base layer text from reader' }
    let(:cells) do
      row_text.each_char.with_index.map do |char, index|
        Shoko::Adapters::Ui::Rendering::Models::LineCell.new(
          cluster: char,
          char_start: index,
          char_end: index + 1,
          display_width: 1,
          screen_x: index
        )
      end
    end
    let(:geometry) do
      Shoko::Adapters::Ui::Rendering::Models::LineGeometry.new(
        page_id: 0,
        column_id: 0,
        row: 1,
        column_origin: 1,
        line_offset: 0,
        plain_text: row_text,
        styled_text: row_text,
        cells: cells
      )
    end
    let(:rendered_lines) { { geometry.key => { geometry: geometry } } }

    it 'blends menu text with a tinted backdrop from the underlying row text' do
      menu = build_menu(rendered_lines: rendered_lines, dictionary_enabled: false)
      writes = []
      surface = Object.new
      surface.define_singleton_method(:write_abs) do |_bounds, row, col, text|
        writes << { row: row, col: col, text: text }
      end

      menu.render(surface, bounds)

      expect(writes.length).to eq(4)
      expect(writes[1][:text]).to include(Shoko::Adapters::Ui::Constants::Ui::TOOLTIP_GLASS_BG_SELECTED)
      ansi_re = /\e\[[0-9;]*m/
      backdrop = writes[1][:text].gsub(ansi_re, '')
      expect(backdrop).to match(/[A-Za-z]/)
      expect(backdrop).to include(' ')
      expect(writes[1][:text]).to include('Create Annotation')
    end
  end
end
