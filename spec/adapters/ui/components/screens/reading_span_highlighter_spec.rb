# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::ReadingSpanHighlighter do
  def reading_line_class = Shoko::Adapters::Ui::Components::Screens::RssArticleLayout::ReadingLine

  def line(content, prefix: [], index: 0)
    reading_line_class.new(
      prefix: prefix, content: content, text: content.map(&:first).join,
      column: prefix.sum { |text, _| text.length }, index: index
    )
  end

  def texts(segments) = segments.map(&:first)

  let(:plain) { line([['hello world', 'FG']]) }

  it 'returns the row untouched when no span touches it' do
    expect(described_class.call(plain, [])).to eq(plain.segments)
  end

  it 'ignores a span that falls outside the row' do
    expect(described_class.call(plain, [{ range: 50..60, style: 'S' }])).to eq(plain.segments)
  end

  it 'cuts a run at the span boundaries' do
    result = described_class.call(plain, [{ range: 6..11, style: 'S' }])

    expect(texts(result)).to eq(['hello ', 'world'])
  end

  it 'adds the span attribute on top of the run colour' do
    result = described_class.call(plain, [{ range: 0..5, style: 'S' }])

    expect(result.first.last).to eq('SFG')
    expect(result.last.last).to eq('FG')
  end

  # Emphasis, links and quote tones must survive being highlighted.
  it 'keeps each run its own colour across a span that covers several' do
    row = line([['bold', 'B'], ['plain', 'P']])

    result = described_class.call(row, [{ range: 0..9, style: 'S' }])

    expect(result.map(&:last)).to eq(%w[SB SP])
  end

  it 'never paints the decoration before the prose' do
    row = line([['quoted', 'FG']], prefix: [['| ', 'DIM']])

    result = described_class.call(row, [{ range: 0..6, style: 'S' }])

    expect(result.first).to eq(['| ', 'DIM'])
    expect(result.last.last).to eq('SFG')
  end

  it 'applies both attributes where two spans overlap' do
    result = described_class.call(plain, [{ range: 0..6, style: 'A' }, { range: 3..11, style: 'B' }])

    overlapping = result.find { |text, _style| text == 'lo ' }

    expect(overlapping.last).to include('A').and include('B')
  end

  it 'offsets spans by the row position in the stream' do
    row = line([['second row', 'FG']], index: 100)

    result = described_class.call(row, [{ range: 107..110, style: 'S' }])

    expect(texts(result)).to eq(['second ', 'row'])
  end

  it 'clips a span that starts before the row' do
    row = line([['tail', 'FG']], index: 10)

    result = described_class.call(row, [{ range: 0..12, style: 'S' }])

    expect(texts(result)).to eq(['ta', 'il'])
    expect(result.first.last).to eq('SFG')
  end
end
