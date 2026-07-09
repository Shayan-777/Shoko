# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::MenuDesign::CanvasList do
  include MenuScreenRenderHelpers

  let(:components) { Shoko::Adapters::Ui::Components }
  let(:metrics) { Shoko::Shared::Terminal::TextMetrics }
  let(:hits) { Shoko::Adapters::Ui::State::MenuHitRegistry.new }
  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:width) { 100 }
  let(:height) { 20 }

  let(:bounds) { components::Rect.new(x: 1, y: 1, width: width, height: height) }
  let(:surface) { components::Surface.new(terminal) }
  let(:frame) { components::MenuDesign::CanvasFrame.new(surface, bounds) }
  let(:list) { described_class.new(surface, bounds, frame: frame, hits: hits) }

  # The last column of the content measure, which the scrollbar owns.
  let(:bar_col) { frame.content_x + frame.content_width - 1 }

  before { terminal.reset! }

  def row_write(row)
    terminal.writes.find { |entry| entry[:row] == row && entry[:col] == frame.content_x }
  end

  def visible(text) = metrics.visible_length(strip_ansi(text))

  describe 'the strip a row occupies' do
    before do
      list.row(row: 5, left: [['L' * 400, nil]], right: [['9.9 MB', nil]],
               selected: true, action: { type: :list_row, list: :browse, index: 0 })
    end

    it 'stops one column short of the scrollbar, so the bar never lands on the row' do
      expect(frame.content_x + visible(row_write(5)[:text]) - 1).to eq(bar_col - 1)
    end

    it 'holds the row text RIGHT_GAP columns clear of the scrollbar' do
      trailing = strip_ansi(row_write(5)[:text])[-described_class::RIGHT_GAP..]

      expect(trailing).to eq(' ' * described_class::RIGHT_GAP)
    end

    it 'keeps the right-hand label whole rather than letting the bar eat its last cell' do
      expect(strip_ansi(row_write(5)[:text])).to include('9.9 MB')
    end

    it 'leaves the scrollbar column outside the row click target' do
      expect(hits.hit(bar_col, 5)).to be_nil
      expect(hits.hit(bar_col - 1, 5)).to eq({ type: :list_row, list: :browse, index: 0 })
    end
  end

  describe 'the scrollbar' do
    before do
      list.row(row: 5, left: [['Row', nil]], selected: false, action: nil)
      list.render_scrollbar(top: 5, height: 4, total: 100, visible: 4, offset: 0)
    end

    it 'draws in the column the strip reserved for it' do
      bar = terminal.writes.select { |entry| entry[:col] == bar_col }

      expect(bar.length).to eq(4)
      expect(bar.map { |entry| strip_ansi(entry[:text]) }.uniq).to eq([described_class::SCROLL_GLYPH])
    end

    it 'stays silent when everything fits' do
      terminal.reset!
      list.render_scrollbar(top: 5, height: 4, total: 4, visible: 4, offset: 0)

      expect(terminal.writes).to be_empty
    end
  end

  describe '#text_width' do
    it 'reports the columns a row may fill: the strip, less the pointer and the gap' do
      pointer = frame.width_of(components::MenuDesign::IconSet.selection_pointer)
      reserved = described_class::SCROLLBAR_WIDTH + described_class::RIGHT_GAP

      expect(list.text_width).to eq(frame.content_width - reserved - pointer)
    end

    it 'measures against a narrowed strip when a well sits beside the list' do
      expect(list.text_width(40)).to eq(list.text_width - (frame.content_width - 40))
    end
  end

  describe 'a multi-row block' do
    before do
      list.block(row: 6, lines: [{ left: [['Title', nil]] }, { left: [['Meta', nil]], right: [['1.0 MB', nil]] }],
                 selected: true, action: { type: :list_row, list: :browse, index: 3 })
    end

    it 'gives every row of the block the same reserved strip' do
      widths = [6, 7].map { |row| visible(row_write(row)[:text]) }

      expect(widths.uniq).to eq([frame.content_width - described_class::SCROLLBAR_WIDTH])
    end

    it 'registers the whole block as one click target' do
      expect(hits.hit(frame.content_x, 7)).to eq({ type: :list_row, list: :browse, index: 3 })
    end
  end
end
