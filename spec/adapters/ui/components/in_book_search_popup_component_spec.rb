# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::InBookSearchPopupComponent do
  def strip_ansi(text)
    text.to_s.gsub(%r{\e\[[0-9;]*[ -/]*[@-~]}, '')
  end

  def build_geometry_row(row:, text:, column_origin: 1, page_id: 0, column_id: 0, line_offset: 0)
    cells = text.each_char.with_index.map do |char, index|
      Shoko::Adapters::Ui::Rendering::Models::LineCell.new(
        cluster: char,
        char_start: index,
        char_end: index + 1,
        display_width: 1,
        screen_x: index
      )
    end

    geometry = Shoko::Adapters::Ui::Rendering::Models::LineGeometry.new(
      page_id: page_id,
      column_id: column_id,
      row: row,
      column_origin: column_origin,
      line_offset: line_offset,
      plain_text: text,
      styled_text: text,
      cells: cells
    )

    { geometry.key => { geometry: geometry } }
  end

  subject(:component) { described_class.new }

  let(:results) do
    [
      { chapter_index: 0, chapter_title: 'One', line_index: 2, before: 'a few', match: 'many', after: 'words here' },
      { chapter_index: 1, chapter_title: 'Two', line_index: 5, before: 'before', match: 'many', after: 'after' },
      { chapter_index: 2, chapter_title: 'Three', line_index: 7, before: 'context', match: 'many', after: 'tail' },
    ]
  end

  describe '#show and #hide' do
    it 'tracks visibility and payload' do
      component.show(query: 'many', results: results, total_matches: 3)

      expect(component).to be_visible
      expect(component.query).to eq('many')
      expect(component.results.length).to eq(3)
      expect(component.total_matches).to eq(3)

      component.hide
      expect(component).not_to be_visible
      expect(component.query).to eq('')
      expect(component.results).to eq([])
    end
  end

  describe '#handle_key' do
    before { component.show(query: '', results: [], total_matches: 0) }

    it 'emits query change for printable input and backspace' do
      expect(component.handle_key('m')).to eq(type: :query_change, query: 'm')
      expect(component.handle_key('a')).to eq(type: :query_change, query: 'ma')
      expect(component.handle_key("\x7F")).to eq(type: :query_change, query: 'm')
    end

    it 'emits close for cancel key' do
      key = Shoko::Shared::KeyDefinitions::ACTIONS[:cancel].first
      expect(component.handle_key(key)).to eq(type: :close)
    end

    it 'treats q as query input instead of closing the popup' do
      expect(component.handle_key('q')).to eq(type: :query_change, query: 'q')
      expect(component).to be_visible
    end

    it 'moves selection on navigation keys' do
      component.show(query: 'many', results: results, total_matches: 3)
      component.instance_variable_set(:@last_visible_cards, 1)
      down = Shoko::Shared::KeyDefinitions::NAVIGATION[:down].first
      up = Shoko::Shared::KeyDefinitions::NAVIGATION[:up].first

      expect(component.handle_key(down)).to eq(type: :scroll)
      expect(component.selected_index).to eq(1)
      expect(component.scroll_offset).to eq(1)

      expect(component.handle_key(up)).to eq(type: :scroll)
      expect(component.selected_index).to eq(0)
      expect(component.scroll_offset).to eq(0)
    end

    it 'submits query on enter only when query changed since last search' do
      component.handle_key('m')

      expect(component.handle_key("\n")).to eq(type: :submit_query, query: 'm')
    end

    it 'opens selected result on enter when query is already searched' do
      component.show(query: 'many', results: results, total_matches: 3)
      outcome = component.handle_key("\n")

      expect(outcome).to include(type: :open_result)
      expect(outcome[:result]).to include(chapter_index: 0, line_index: 2)
    end
  end

  describe '#render' do
    let(:terminal) { Shoko::TestSupport::TerminalDouble }
    let(:surface) { Shoko::Adapters::Ui::Components::Surface.new(terminal) }
    let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 120, height: 40) }

    before do
      terminal.reset!
      component.show(query: 'many', results: results, total_matches: 3)
    end

    it 'blends backdrop glyphs into panel background in dark mode' do
      layout = component.send(:overlay_layout, bounds)
      rendered_lines = {}
      (layout.origin_y..(layout.origin_y + layout.height - 1)).each do |row|
        rendered_lines.merge!(build_geometry_row(row: row, text: ('backdrop dark ' * 24).strip, line_offset: row))
      end
      component.update_rendered_lines(rendered_lines)

      component.render(surface, bounds)

      rendered = terminal.writes.map { |write| write[:text] }.join("\n")
      sample = component.send(:backdrop_segment, layout.origin_y, layout.origin_x, 40)

      expect(sample).to include('backdrop')
      expect(rendered).to include(described_class::BACKDROP_FG_DARK)
      expect(rendered).to include(Shoko::Adapters::Ui::Constants::Ui::TOOLTIP_BG_DEFAULT)
      expect(strip_ansi(rendered)).to include('In-Book Search')
    end

    it 'uses light-mode backdrop attenuation when color mode is light' do
      component.update_color_mode(:light)
      layout = component.send(:overlay_layout, bounds)
      rendered_lines = {}
      (layout.origin_y..(layout.origin_y + layout.height - 1)).each do |row|
        rendered_lines.merge!(build_geometry_row(row: row, text: ('light layer ' * 24).strip, line_offset: row))
      end
      component.update_rendered_lines(rendered_lines)

      component.render(surface, bounds)

      rendered = terminal.writes.map { |write| write[:text] }.join("\n")
      expect(rendered).to include(described_class::BACKDROP_FG_LIGHT)
      expect(rendered).to include(described_class::PANEL_BG_LIGHT)
      expect(rendered).to include(described_class::PANEL_FG_LIGHT)
    end
  end

  describe 'overlay sizing' do
    it 'respects minimum dimensions' do
      bounds = Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 70, height: 22)
      layout = component.send(:overlay_layout, bounds)

      expect(layout.width).to be >= 62
      expect(layout.height).to be >= 16
    end
  end
end
