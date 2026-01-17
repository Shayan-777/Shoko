# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Terminal::TextMetrics do
  describe '.visible_length' do
    it 'ignores ANSI sequences and expands tabs' do
      text = "\e[31mHi\t!\e[0m"
      expect(described_class.visible_length(text)).to eq(5)
    end
  end

  describe '.truncate_to' do
    it 'clips text to the requested width' do
      expect(described_class.truncate_to('abcdef', 3)).to eq('abc')
    end

    it 'treats newlines as spaces when truncating' do
      expect(described_class.truncate_to("ab\ncd", 3)).to eq('ab ')
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
end
