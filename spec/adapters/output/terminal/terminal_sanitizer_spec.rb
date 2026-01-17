# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Terminal::TerminalSanitizer do
  describe '.sanitize' do
    it 'removes ANSI and control characters' do
      input = "\e[31mHello\e[0m\x07"
      expect(described_class.sanitize(input)).to eq('Hello')
    end

    it 'preserves newlines when requested' do
      input = "a\nb"
      expect(described_class.sanitize(input, preserve_newlines: true)).to eq("a\nb")
    end
  end

  describe '.sanitize_xml_source' do
    it 'decodes numeric control references before sanitizing' do
      input = 'hi&#x0A;there'
      expect(described_class.sanitize_xml_source(input, preserve_newlines: true)).to eq("hi\nthere")
    end
  end

  describe '.printable_char?' do
    it 'rejects control characters' do
      expect(described_class.printable_char?("\n")).to be(false)
    end

    it 'accepts printable characters' do
      expect(described_class.printable_char?('A')).to be(true)
    end
  end
end
