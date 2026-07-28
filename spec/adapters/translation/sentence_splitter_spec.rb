# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Translation::SentenceSplitter do
  def segment_texts(text)
    described_class.segments(text).map(&:first)
  end

  it 'returns nothing for empty input' do
    expect(described_class.segments('')).to eq([])
    expect(described_class.segments("  \n  ")).to eq([])
  end

  it 'keeps a single sentence whole' do
    expect(segment_texts('Hello there.')).to eq(['Hello there.'])
  end

  it 'splits at sentence boundaries regardless of the next letter case' do
    expect(segment_texts('First one. Second one! Third?')).to eq(
      ['First one.', 'Second one!', 'Third?']
    )
    expect(segment_texts('First one. second one.')).to eq(['First one.', 'second one.'])
  end

  it 'does not split after abbreviations followed by lowercase' do
    expect(segment_texts('It costs approx. five euro.')).to eq(['It costs approx. five euro.'])
  end

  it 'splits after quoted sentence ends' do
    expect(segment_texts('"Stop." He ran away.')).to eq(['"Stop."', 'He ran away.'])
  end

  it 'preserves exact sentence and paragraph separators' do
    segments = described_class.segments("One. Two.\n\nThree.")
    expect(segments).to eq([['One.', ' '], ['Two.', "\n\n"], ['Three.', '']])
    expect(segments.map { |content, separator| "#{content}#{separator}" }.join).to eq("One. Two.\n\nThree.")
  end

  it 'supports non-Latin sentence punctuation' do
    expect(segment_texts('第一句。第二句！第三句？')).to eq(['第一句。', '第二句！', '第三句？'])
    expect(segment_texts("第一句。\n第二句！")).to eq(['第一句。', '第二句！'])
  end

  it 'does not split common titles' do
    expect(segment_texts('Dr. Smith arrived. Then left.')).to eq(['Dr. Smith arrived.', 'Then left.'])
  end

  it 'does not mistake decimal points for sentence boundaries' do
    expect(segment_texts('It costs 3.14 euros. next sentence.')).to eq(
      ['It costs 3.14 euros.', 'next sentence.']
    )
  end

  it 'retains leading whitespace on translatable content' do
    segments = described_class.segments('  One. Two.')
    expect(segments.first.first).to eq('  One.')
    expect(segments.map { |content, separator| "#{content}#{separator}" }.join).to eq('  One. Two.')
  end

  it 'chunks overlong sentences at phrase boundaries under the byte budget' do
    long = "#{'word ' * 400}end, #{'tail ' * 100}stop"
    chunks = described_class.segments(long).map(&:first)
    expect(chunks.length).to be > 1
    expect(chunks).to all(satisfy { |c| c.bytesize <= described_class::MAX_SEGMENT_BYTES })
    expect(chunks.join(' ').split).to eq(long.split)
  end

  it 'chunks multibyte text without splitting codepoints' do
    long = "#{'täht ' * 400}lõpp"
    chunks = described_class.segments(long).map(&:first)
    expect(chunks).to all(satisfy { |c| c.valid_encoding? && c.bytesize <= described_class::MAX_SEGMENT_BYTES })
  end
end
