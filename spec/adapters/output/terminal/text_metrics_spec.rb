# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Terminal::TextMetrics do
  describe '.visible_length' do
    it 'ignores ANSI sequences and expands tabs' do
      text = "\e[31mHi\t!\e[0m"
      expect(described_class.visible_length(text)).to eq(5)
    end

    it 'counts wide CJK characters as width 2' do
      text = "\u{53E4}\u{6587}"
      expect(described_class.visible_length(text)).to eq(4)
    end

    it 'treats combining marks as zero-width in grapheme clusters' do
      text = "e\u{0301}"
      expect(described_class.visible_length(text)).to eq(1)
    end

    it 'treats emoji modifiers as a single double-width glyph' do
      text = "\u{1F44D}\u{1F3FD}"
      expect(described_class.visible_length(text)).to eq(2)
    end

    it 'treats ZWJ emoji sequences as double-width glyphs' do
      text = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
      expect(described_class.visible_length(text)).to eq(2)
    end

    it 'treats keycap emoji sequences as double-width glyphs' do
      text = "1\u{FE0F}\u{20E3}"
      expect(described_class.visible_length(text)).to eq(2)
    end

    it 'returns the same width with cache enabled and disabled' do
      text = "\e[31mWide 日本語 😀 and tabs\t!\e[0m"

      disabled = described_class.with_visible_length_cache(enabled: false) do
        described_class.clear_visible_length_cache
        described_class.visible_length(text)
      end

      enabled = described_class.with_visible_length_cache(enabled: true) do
        described_class.clear_visible_length_cache
        described_class.visible_length(text)
      end

      expect(enabled).to eq(disabled)
    end

    it 'returns the same width with ASCII fast path enabled and disabled' do
      text = ("\e[31mASCII with tabs\tand ANSI reset\e[0m " * 4).strip

      baseline = described_class.with_ascii_fast_path(enabled: false) do
        described_class.visible_length(text)
      end

      optimized = described_class.with_ascii_fast_path(enabled: true) do
        described_class.visible_length(text)
      end

      expect(optimized).to eq(baseline)
    end
  end

  describe '.truncate_to' do
    it 'clips text to the requested width' do
      expect(described_class.truncate_to('abcdef', 3)).to eq('abc')
    end

    it 'treats newlines as spaces when truncating' do
      expect(described_class.truncate_to("ab\ncd", 3)).to eq('ab ')
    end

    it 'returns the same result with ASCII fast path enabled and disabled' do
      text = ('The quick brown fox jumps over the lazy dog 1234567890 ' * 5).strip

      baseline = described_class.with_ascii_fast_path(enabled: false) do
        described_class.truncate_to(text, 80)
      end

      optimized = described_class.with_ascii_fast_path(enabled: true) do
        described_class.truncate_to(text, 80)
      end

      expect(optimized).to eq(baseline)
    end
  end

  describe '.pad_right' do
    it 'pads the right side to the requested width' do
      result = described_class.pad_right('hi', 5)
      expect(described_class.visible_length(result)).to eq(5)
      expect(result).to start_with('hi')
    end
  end

  describe '.wrap_cells' do
    it 'wraps lines on width boundaries without losing content' do
      lines = described_class.wrap_cells('one two three', 6)
      expect(lines.length).to be > 1
      collapsed = lines.join(' ').delete(' ')
      expect(collapsed).to include('one')
      expect(collapsed).to include('three')
    end
  end

  describe '.wrap_plain_text' do
    it 'splits long unbroken words to stay within width' do
      word = 'supercalifragilisticexpialidocious'
      lines = described_class.wrap_plain_text(word, 10)

      expect(lines.length).to be > 1
      expect(lines.join).to eq(word)
      expect(lines.all? { |line| described_class.visible_length(line) <= 10 }).to be(true)
    end

    it 'preserves surrounding words while splitting long tokens' do
      text = 'alpha supercalifragilistic beta'
      lines = described_class.wrap_plain_text(text, 10)

      collapsed = lines.join.gsub(/\s+/, '')
      expect(collapsed).to eq(text.gsub(/\s+/, ''))
      expect(lines.all? { |line| described_class.visible_length(line) <= 10 }).to be(true)
    end

    it 'returns the same wrapped result with wrap cache enabled and disabled' do
      text = ('alpha beta gamma delta epsilon zeta eta theta iota kappa ' * 5).strip

      baseline = described_class.with_wrap_plain_text_cache(enabled: false) do
        described_class.clear_wrap_plain_text_cache
        described_class.wrap_plain_text(text, 24)
      end

      optimized = described_class.with_wrap_plain_text_cache(enabled: true) do
        described_class.clear_wrap_plain_text_cache
        described_class.wrap_plain_text(text, 24)
      end

      expect(optimized).to eq(baseline)
    end
  end
end
