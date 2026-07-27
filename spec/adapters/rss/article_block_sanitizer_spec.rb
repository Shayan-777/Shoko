# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Rss::ArticleBlockSanitizer do
  subject(:sanitizer) { described_class.new(max_text_length: 40) }

  def block(text, type: :paragraph, styles: {}, metadata: {})
    Shoko::Core::Models::ContentBlock.new(
      type: type,
      segments: [Shoko::Core::Models::TextSegment.new(text: text, styles: styles)],
      metadata: metadata
    )
  end

  # Article text is third-party page content: an escape sequence in it would
  # repaint the reader's terminal.
  it 'strips control sequences from block text' do
    result = sanitizer.call([block("safe\e[31mred\e[0m")])

    expect(result.first.text).to eq('safered')
  end

  it 'strips control sequences from list markers' do
    result = sanitizer.call([block('item', type: :list_item, metadata: { marker: "\e[5m•" })])

    expect(result.first.metadata[:marker]).not_to include("\e")
  end

  it 'strips control sequences from link targets' do
    result = sanitizer.call([block('text', styles: { link: true, href: "http://x\e[2J" })])

    expect(result.first.segments.first.styles[:href]).not_to include("\e")
  end

  it 'flattens newlines, because a block is a line' do
    expect(sanitizer.call([block("one\ntwo")]).first.text).to eq('one two')
  end

  it 'drops blocks left empty by sanitizing' do
    expect(sanitizer.call([block("\e[31m"), block('kept')]).map(&:text)).to eq(['kept'])
  end

  it 'keeps textless structural blocks' do
    expect(sanitizer.call([block('', type: :rule)]).map(&:type)).to eq([:rule])
  end

  it 'preserves inline styles' do
    result = sanitizer.call([block('bold', styles: { bold: true })])

    expect(result.first.segments.first.styles).to eq({ bold: true })
  end

  describe 'the total text ceiling' do
    it 'enforces the hard ceiling and truncates the last block safely' do
      blocks = [block('a' * 30), block('b' * 30), block('c' * 30)]

      result = sanitizer.call(blocks)

      expect(result.map(&:text)).to eq(['a' * 30, 'b' * 10])
      expect(result.sum { |block| block.text.length }).to eq(40)
    end

    it 'always keeps at least the first block' do
      expect(described_class.new(max_text_length: 5).call([block('a' * 500)]).length).to eq(1)
    end

    it 'keeps everything when the article is within budget' do
      expect(sanitizer.call([block('short'), block('also short')]).length).to eq(2)
    end
  end
end
