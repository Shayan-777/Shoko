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

  it 'splits at sentence boundaries before capitalized starts' do
    expect(segment_texts('First one. Second one! Third?')).to eq(
      ['First one.', 'Second one!', 'Third?']
    )
  end

  it 'does not split after abbreviations followed by lowercase' do
    expect(segment_texts('It costs approx. five euro.')).to eq(['It costs approx. five euro.'])
  end

  it 'splits after quoted sentence ends' do
    expect(segment_texts('"Stop." He ran away.')).to eq(['"Stop."', 'He ran away.'])
  end

  it 'marks paragraph breaks and keeps them out of mid-paragraph splits' do
    segments = described_class.segments("One. Two.\n\nThree.")
    expect(segments).to eq([['One.', false], ['Two.', true], ['Three.', false]])
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
