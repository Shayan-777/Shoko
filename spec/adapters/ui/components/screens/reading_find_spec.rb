# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::ReadingFind do
  def reading_line_class = Shoko::Adapters::Ui::Components::Screens::RssArticleLayout::ReadingLine

  def lines_from(texts)
    cursor = 0
    texts.map do |text|
      line = reading_line_class.new(content: [[text, 'FG']], text: text, index: cursor)
      cursor += text.length + 1
      line
    end
  end

  describe '.matches' do
    it 'finds every occurrence in reading order' do
      expect(described_class.matches('drohne und drohne', 'drohne').map(&:first)).to eq([0, 11])
    end

    it 'ignores case' do
      expect(described_class.matches('Die Drohne', 'drohne').length).to eq(1)
    end

    it 'spans exactly the query' do
      match = described_class.matches('die Drohne kam', 'Drohne').first

      expect('die Drohne kam'[match]).to eq('Drohne')
    end

    it 'finds overlapping occurrences' do
      expect(described_class.matches('aaaa', 'aa').length).to eq(3)
    end

    it 'treats the query literally rather than as a pattern' do
      expect(described_class.matches('a.c and abc', 'a.c').length).to eq(1)
    end

    it 'finds nothing for a blank query' do
      expect(described_class.matches('text', '')).to eq([])
      expect(described_class.matches('text', '   ')).to eq([])
      expect(described_class.matches('text', nil)).to eq([])
    end

    it 'matches across a line break in the stream' do
      expect(described_class.matches("erste\nzweite", "e\nz").length).to eq(1)
    end
  end

  describe '.wrap_index' do
    it 'wraps past the end' do
      expect(described_class.wrap_index(3, 3)).to eq(0)
    end

    it 'wraps before the start' do
      expect(described_class.wrap_index(-1, 3)).to eq(2)
    end

    it 'is zero when there is nothing to step through' do
      expect(described_class.wrap_index(5, 0)).to eq(0)
    end
  end

  describe '.scroll_to' do
    let(:lines) { lines_from(Array.new(20) { |i| "line #{i}" }) }

    def match_on(row) = (lines[row].index...(lines[row].index + 4))

    it 'leaves the scroll alone when the match is already visible' do
      expect(described_class.scroll_to(match_on(3), lines, scroll: 2, visible: 5)).to eq(2)
    end

    it 'scrolls up to a match above the window' do
      expect(described_class.scroll_to(match_on(1), lines, scroll: 10, visible: 5)).to eq(1)
    end

    it 'scrolls down just far enough to reveal a match below the window' do
      expect(described_class.scroll_to(match_on(12), lines, scroll: 0, visible: 5)).to eq(8)
    end

    it 'keeps the scroll when the match cannot be located' do
      expect(described_class.scroll_to(9_999..10_000, lines, scroll: 4, visible: 5)).to eq(4)
    end
  end
end
