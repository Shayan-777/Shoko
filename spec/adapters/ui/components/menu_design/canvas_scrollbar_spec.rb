# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::MenuDesign::CanvasScrollbar do
  include MenuScreenRenderHelpers

  let(:width) { 40 }
  let(:height) { 20 }
  let(:palette) { Shoko::Adapters::Ui::Components::StatusBar::Palette }
  let(:bounds) { Shoko::Adapters::Ui::Components::Rect.new(x: 1, y: 1, width: width, height: height) }

  def render(total:, visible:, offset:, rows: visible, top: 1)
    terminal = Shoko::TestSupport::TerminalDouble
    terminal.reset!
    surface = Shoko::Adapters::Ui::Components::Surface.new(terminal)
    frame = Shoko::Adapters::Ui::Components::MenuDesign::CanvasFrame.new(surface, bounds)
    described_class.render(
      surface: surface, bounds: bounds, frame: frame,
      top: top, height: rows, total: total, visible: visible, offset: offset
    )
    terminal.writes
  end

  def thumb_rows(writes)
    writes.select { |entry| entry[:text].include?(palette::LIST_SCROLL_THUMB_FG) }.map { |entry| entry[:row] }
  end

  it 'draws nothing when everything already fits' do
    expect(render(total: 5, visible: 10, offset: 0)).to be_empty
  end

  it 'draws nothing when there is no room' do
    expect(render(total: 100, visible: 10, offset: 0, rows: 0)).to be_empty
  end

  it 'draws a track spanning the whole area' do
    expect(render(total: 100, visible: 10, offset: 0).map { |entry| entry[:row] }).to eq((1..10).to_a)
  end

  it 'puts the thumb at the top when unscrolled' do
    expect(thumb_rows(render(total: 100, visible: 10, offset: 0)).first).to eq(1)
  end

  it 'puts the thumb at the bottom when fully scrolled' do
    expect(thumb_rows(render(total: 100, visible: 10, offset: 90)).last).to eq(10)
  end

  it 'sizes the thumb in proportion to how much is visible' do
    small = thumb_rows(render(total: 100, visible: 10, offset: 0)).length
    large = thumb_rows(render(total: 20, visible: 10, offset: 0)).length

    expect(large).to be > small
  end

  it 'keeps the thumb at least one row even for a very long article' do
    expect(thumb_rows(render(total: 10_000, visible: 10, offset: 0)).length).to eq(1)
  end

  it 'draws in the last column of the content measure' do
    frame = Shoko::Adapters::Ui::Components::MenuDesign::CanvasFrame.new(nil, bounds)
    columns = render(total: 100, visible: 10, offset: 0).map { |entry| entry[:col] }.uniq

    expect(columns).to eq([frame.content_x + frame.content_width - described_class::WIDTH])
  end

  it 'honours the row it is told to start at' do
    expect(render(total: 100, visible: 5, offset: 0, top: 7).map { |entry| entry[:row] }).to eq((7..11).to_a)
  end
end
