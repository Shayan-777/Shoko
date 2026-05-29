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

  let(:results) do
    [
      {
        chapter_index: 0,
        chapter_title: 'One',
        line_index: 2,
        before: 'a few',
        match: 'many',
        after: 'words here',
        line_space: :wrapped,
        page_index: 4,
      },
      { chapter_index: 1, chapter_title: 'Two', line_index: 5, before: 'before', match: 'many', after: 'after' },
      { chapter_index: 2, chapter_title: 'Three', line_index: 7, before: 'context', match: 'many', after: 'tail' },
    ]
  end

  let(:search_state) do
    {
      mode: :in_book_search,
      search_query: 'many',
      search_results: results,
      search_results_query: 'many',
      search_total_matches: 3,
      search_selected_index: 0,
    }
  end
  let(:reader_state_reader) { instance_double('ReaderStateReader', **search_state) }

  subject(:component) { described_class.new(reader_state_reader: reader_state_reader) }

  describe '#visible?' do
    it 'tracks the in-book search mode from state' do
      expect(component).to be_visible

      allow(reader_state_reader).to receive(:mode).and_return(:read)
      expect(component).not_to be_visible
    end
  end

  describe '#render' do
    let(:terminal) { Shoko::TestSupport::TerminalDouble }
    let(:surface) { Shoko::Adapters::Ui::Components::Surface.new(terminal) }
    let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 120, height: 40) }

    before { terminal.reset! }

    it 'renders search content pulled from state' do
      component.render(surface, bounds)

      rendered = strip_ansi(terminal.writes.map { |write| write[:text] }.join("\n"))
      expect(rendered).to include('In-Book Search')
      expect(rendered).to include('many')
    end

    it 'does not render when search mode is inactive' do
      allow(reader_state_reader).to receive(:mode).and_return(:read)

      component.render(surface, bounds)

      expect(terminal.writes).to be_empty
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
      palette = Shoko::Adapters::Ui::Constants::ComponentPalettes.fetch(:in_book_search_popup, :dark)

      expect(sample).to include('backdrop')
      expect(rendered).to include(palette[:backdrop_fg])
      expect(rendered).to include(palette[:panel_bg])
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
      palette = Shoko::Adapters::Ui::Constants::ComponentPalettes.fetch(:in_book_search_popup, :light)

      expect(rendered).to include(palette[:backdrop_fg])
      expect(rendered).to include(palette[:panel_bg])
      expect(rendered).to include(palette[:panel_fg])
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
