# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::InBookSearchPopupComponent do
  def strip_ansi(text)
    text.to_s.gsub(%r{\e\[[0-9;]*[ -/]*[@-~]}, '')
  end

  let(:results) do
    [
      { chapter_index: 0, chapter_title: 'One', line_index: 2, before: 'a few ', match: 'many', after: ' words here' },
      { chapter_index: 1, chapter_title: 'Two', line_index: 5, before: 'before ', match: 'many', after: ' after' },
      { chapter_index: 2, chapter_title: 'Three', line_index: 7, before: 'context ', match: 'many', after: ' tail' },
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

  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:surface) { Shoko::Adapters::Ui::Components::Surface.new(terminal) }
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 100, height: 20) }

  before { terminal.reset! }

  def rendered_rows
    terminal.writes.group_by { |write| write[:row] }.transform_values do |writes|
      strip_ansi(writes.map { |write| write[:text] }.join)
    end
  end

  describe '#visible?' do
    it 'tracks the in-book search mode from state' do
      expect(component).to be_visible

      allow(reader_state_reader).to receive(:mode).and_return(:read)
      expect(component).not_to be_visible
    end
  end

  describe '#render' do
    it 'does not render when search mode is inactive' do
      allow(reader_state_reader).to receive(:mode).and_return(:read)
      component.render(surface, bounds)
      expect(terminal.writes).to be_empty
    end

    it 'renders nothing when there are no results yet' do
      allow(reader_state_reader).to receive(:search_results).and_return([])
      component.render(surface, bounds)
      expect(terminal.writes).to be_empty
    end

    it 'lists results above the bar, never on the bottom bar row' do
      component.render(surface, bounds)

      rows = terminal.writes.map { |write| write[:row] }
      expect(rows).not_to include(bounds.height)
      expect(rows.max).to be < bounds.height

      text = rendered_rows.values.join("\n")
      expect(text).to include('many')
      expect(text).to include('line')
    end

    it 'snaps flush to the left and caps its width on the right' do
      component.render(surface, bounds)
      writes = terminal.writes

      expect(writes.map { |write| write[:col] }.uniq).to eq([1])

      expected_width = [bounds.width, described_class::MAX_WIDTH].min
      bottom = writes.select { |write| write[:row] == bounds.height - 1 }
      raw = bottom.map { |write| write[:text] }.join
      expect(Shoko::Shared::Terminal::TextMetrics.visible_length(raw)).to eq(expected_width)
    end

    it 'orders results top-to-bottom with the last nearest the bar' do
      component.render(surface, bounds)
      rows = rendered_rows

      row_for = ->(label) { rows.find { |_row, text| text.include?(label) }.first }
      expect(row_for.call('One')).to be < row_for.call('Two')
      expect(row_for.call('Two')).to be < row_for.call('Three')
      expect(row_for.call('Three')).to eq(bounds.height - 1)
    end

    it 'marks the selected result with a pointer' do
      allow(reader_state_reader).to receive(:search_selected_index).and_return(1)
      component.render(surface, bounds)

      pointer_row = rendered_rows.find { |_row, text| text.include?('▸') }
      expect(pointer_row).not_to be_nil
      expect(pointer_row.last).to include('Two')
    end

    it 'shows a "more" hint for results scrolled off the top' do
      many = Array.new(14) do |i|
        { chapter_index: i, chapter_title: "Ch#{i}", line_index: i, before: 'x ', match: 'many', after: ' y' }
      end
      allow(reader_state_reader).to receive(:search_results).and_return(many)
      allow(reader_state_reader).to receive(:search_selected_index).and_return(13)

      component.render(surface, bounds)
      expect(rendered_rows.values.join).to match(/↑ \d+ more/)
    end
  end
end
