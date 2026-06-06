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

    context 'when the reader centers its text and leaves an empty left margin' do
      let(:wide) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: 200, height: 30) }
      let(:gap) { Shoko::Adapters::Ui::Components::BottomLeftPanel::SIDE_GAP }

      it 'shrinks into the margin instead of overlapping the text column' do
        component.content_left_edge = 80 # the book text starts at column 80
        component.render(surface, wide)

        bottom = terminal.writes.select { |write| write[:row] == wide.height - 1 }
        raw = bottom.map { |write| write[:text] }.join
        expect(Shoko::Shared::Terminal::TextMetrics.visible_length(raw)).to eq(80 - 1 - gap)
      end

      it 'gains rows in return for the width it gives up' do
        many = Array.new(14) do |i|
          { chapter_index: i, chapter_title: "Ch#{i}", line_index: i, before: 'x ', match: 'many', after: ' y' }
        end
        allow(reader_state_reader).to receive(:search_results).and_return(many)

        component.content_left_edge = 80
        component.render(surface, wide)
        constrained_top = terminal.writes.map { |write| write[:row] }.min

        terminal.reset!
        component.content_left_edge = nil
        component.render(surface, wide)
        natural_top = terminal.writes.map { |write| write[:row] }.min

        expect(constrained_top).to be < natural_top
      end
    end

    it 'orders results top-to-bottom with the last nearest the bar' do
      component.render(surface, bounds)
      rows = rendered_rows

      row_for = ->(label) { rows.find { |_row, text| text.include?(label) }.first }
      expect(row_for.call('ch. 1')).to be < row_for.call('ch. 2')
      expect(row_for.call('ch. 2')).to be < row_for.call('ch. 3')
      expect(row_for.call('ch. 3')).to eq(bounds.height - 1)
    end

    it 'marks the whole selected entry with a bar down all three of its rows' do
      allow(reader_state_reader).to receive(:search_selected_index).and_return(1)
      component.render(surface, bounds)

      marked = rendered_rows.select { |_row, text| text.include?('▋') }.keys.sort
      expect(marked.size).to eq(3) # exactly the selected entry's three rows
      expect(marked).to eq([marked.first, marked.first + 1, marked.first + 2]) # contiguous block
      expect(rendered_rows.values.join("\n")).to include('ch. 2') # and it is the selected result
    end

    it 'lays each result out as three rows: two snippet rows then the location' do
      single = [{ chapter_index: 11, chapter_title: 'Health Club', line_index: 45, page_index: 38,
                  before: (['lead'] * 12).join(' '), match: 'whale', after: (['tail'] * 12).join(' ') }]
      allow(reader_state_reader).to receive(:search_results).and_return(single)
      allow(reader_state_reader).to receive(:search_selected_index).and_return(0)
      component.render(surface, bounds)

      block = rendered_rows.select { |_row, text| text.include?('▋') }.keys.sort # selected → all 3 rows
      expect(block.size).to eq(3)
      expect("#{rendered_rows[block[0]]}#{rendered_rows[block[1]]}").to include('whale') # match on a snippet row
      location = rendered_rows[block[2]]
      expect(location).to include('page 39')
      expect(location).to include('ch. 12')
      expect(location).to include('line 46')
    end

    it 'shows the per-page line number in the location when paginated' do
      single = [{ chapter_index: 1, line_index: 791, page_index: 38, page_line_index: 16,
                  before: 'some', match: 'word', after: 'here' }]
      allow(reader_state_reader).to receive(:search_results).and_return(single)
      allow(reader_state_reader).to receive(:search_selected_index).and_return(0)
      component.render(surface, bounds)

      location = rendered_rows.values.join("\n")
      expect(location).to include('page 39 - ch. 2 - line 17') # per-page line (16 + 1), not 792
      expect(location).not_to include('line 792')
    end

    it 'flows context across both snippet rows, filling them when ample context exists' do
      before = (%w[alpha beta gamma delta epsilon zeta eta theta] * 2).join(' ')
      after = (%w[one two three four five six seven eight] * 2).join(' ')
      single = [{ chapter_index: 0, line_index: 0, before: before, match: 'MATCH', after: after }]
      allow(reader_state_reader).to receive(:search_results).and_return(single)
      allow(reader_state_reader).to receive(:search_selected_index).and_return(0)
      component.render(surface, bounds)

      block = rendered_rows.select { |_row, text| text.include?('▋') }.keys.sort
      body = ->(row) { rendered_rows[row].sub('▋', '').strip }
      # both snippet rows carry substantial context (no awkward near-empty line)
      expect(body.call(block[0]).length).to be > 40
      expect(body.call(block[1]).length).to be > 40
      expect("#{rendered_rows[block[0]]}#{rendered_rows[block[1]]}").to include('MATCH')
    end

    it 'shows a scrollbar on the panel right edge when results overflow' do
      many = Array.new(20) do |i|
        { chapter_index: i, chapter_title: "Ch#{i}", line_index: i, before: 'x ', match: 'many', after: ' y' }
      end
      allow(reader_state_reader).to receive(:search_results).and_return(many)
      component.render(surface, bounds)

      right_edge = [bounds.width, described_class::MAX_WIDTH].min
      glyph_writes = terminal.writes.select { |write| strip_ansi(write[:text]) == described_class::SCROLL_GLYPH }
      expect(glyph_writes).not_to be_empty
      expect(glyph_writes.map { |write| write[:col] }.uniq).to eq([right_edge]) # scrollbar on the right
      expect(terminal.writes.map { |write| write[:col] }).to include(1)         # content stays flush-left
    end

    it 'keeps a blank column between the snippet text and the scrollbar' do
      long = (['lorem'] * 60).join(' ')
      many = Array.new(20) do |i|
        { chapter_index: i, line_index: i, before: long, match: 'lorem', after: long }
      end
      allow(reader_state_reader).to receive(:search_results).and_return(many)
      component.render(surface, bounds)

      width = [bounds.width, described_class::MAX_WIDTH].min # scrollbar sits at this column
      rule_row = terminal.writes.map { |write| write[:row] }.min # the top border spans full width
      content_rows = terminal.writes.select { |write| write[:col] == 1 && write[:row] > rule_row }
      # rightmost text column across the snippet/location rows (trailing padding stripped)
      rightmost = content_rows.map { |write| strip_ansi(write[:text]).rstrip.length }.max
      expect(rightmost).to be <= width - 2 # at least one blank column before the scrollbar
      expect(rightmost).to be >= width - 10 # ...and the text still fills the row (gap is real, not slack)
    end

    it 'keeps a blank right margin even when no scrollbar is shown' do
      long = (['lorem'] * 40).join(' ')
      single = [{ chapter_index: 0, line_index: 0, before: long, match: 'lorem', after: long }]
      allow(reader_state_reader).to receive(:search_results).and_return(single)
      allow(reader_state_reader).to receive(:search_selected_index).and_return(0)
      component.render(surface, bounds)

      joined = terminal.writes.map { |write| strip_ansi(write[:text]) }.join
      expect(joined).not_to include(described_class::SCROLL_GLYPH) # the single result fits — no scrollbar

      width = [bounds.width, described_class::MAX_WIDTH].min
      rule_row = terminal.writes.map { |write| write[:row] }.min
      content_rows = terminal.writes.select { |write| write[:col] == 1 && write[:row] > rule_row }
      rightmost = content_rows.map { |write| strip_ansi(write[:text]).rstrip.length }.max
      expect(rightmost).to be <= width - 1 # one blank column before the panel edge
      expect(rightmost).to be >= width - 10 # ...and the text still fills the row
    end

    it 'omits the scrollbar when every result fits' do
      component.render(surface, bounds) # the three default results all fit

      expect(terminal.writes.map { |write| write[:col] }.uniq).to eq([1])
      joined = terminal.writes.map { |write| strip_ansi(write[:text]) }.join
      expect(joined).not_to include(described_class::SCROLL_GLYPH)
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
