# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Ui::TextUtils do
  describe '.wrap_prose' do
    it 'wraps words within the width' do
      expect(described_class.wrap_prose('one two three four', 9)).to eq(['one two', 'three', 'four'])
    end

    it 'preserves hard newlines and blank lines' do
      expect(described_class.wrap_prose("first\n\nsecond", 20)).to eq(['first', '', 'second'])
    end

    it 'splits a word longer than the width instead of overflowing' do
      lines = described_class.wrap_prose('see https://example.com/very/long/path here', 12)

      expect(lines.first).to eq('see')
      expect(lines).to all(satisfy { |line| Shoko::Shared::Terminal::TextMetrics.visible_length(line) <= 12 })
      expect(lines.join).to include('https://exam')
    end

    it 'measures display width, not characters' do
      lines = described_class.wrap_prose('魚魚魚 魚魚', 6)

      expect(lines).to eq(%w[魚魚魚 魚魚])
    end
  end

  describe '.wrap_indexed' do
    it 'returns one row with a zero start for short text' do
      expect(described_class.wrap_indexed('hello', 10)).to eq([{ text: 'hello', start: 0 }])
    end

    it 'breaks at the last space and keeps the break space on its row' do
      rows = described_class.wrap_indexed('alpha beta gamma', 11)

      expect(rows).to eq([
                           { text: 'alpha beta ', start: 0 },
                           { text: 'gamma', start: 11 },
                         ])
    end

    it 'preserves every character so row starts tile the text' do
      text = 'the quick brown fox jumps over the lazy dog'
      rows = described_class.wrap_indexed(text, 10)

      expect(rows.map { |row| row[:text] }.join).to eq(text)
      rows.each_cons(2) do |left, right|
        expect(left[:start] + left[:text].length).to eq(right[:start])
      end
    end

    it 'consumes hard newlines as breaks and keeps blank rows' do
      rows = described_class.wrap_indexed("ab\n\ncd", 10)

      expect(rows).to eq([
                           { text: 'ab', start: 0 },
                           { text: '', start: 3 },
                           { text: 'cd', start: 4 },
                         ])
    end

    it 'hard-splits an unbroken word at the width' do
      rows = described_class.wrap_indexed('abcdefghij', 4)

      expect(rows.map { |row| row[:text] }).to eq(%w[abcd efgh ij])
    end

    it 'breaks wide characters on display width, not character count' do
      rows = described_class.wrap_indexed('魚魚魚魚', 4)

      expect(rows.map { |row| row[:text] }).to eq(%w[魚魚 魚魚])
      expect(rows.map { |row| row[:start] }).to eq([0, 2])
    end

    it 'always yields one row for empty text' do
      expect(described_class.wrap_indexed('', 8)).to eq([{ text: '', start: 0 }])
    end
  end

  describe '.wrap_words' do
    it 'falls back to cell wrapping for oversized words' do
      expect(described_class.wrap_words('abcdef', 3)).to eq(%w[abc def])
    end
  end
end
