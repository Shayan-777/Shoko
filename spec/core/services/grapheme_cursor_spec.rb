# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Services::GraphemeCursor do
  let(:text) { "Ame\u0301lie 👩🏽‍💻 🇩🇪" }

  it 'returns only complete grapheme boundaries' do
    boundaries = described_class.boundaries(text)

    expect(boundaries).to eq([0, 1, 2, 4, 5, 6, 7, 8, 12, 13, 15])
    expect(boundaries.map { |index| text[0...index] }).to all(be_valid_encoding)
  end

  it 'moves over combining sequences, emoji modifiers, ZWJ sequences, and flags atomically' do
    clusters = ["e\u0301", '👩🏽‍💻', '🇩🇪']

    clusters.each do |cluster|
      sample = "a#{cluster}b"
      before = 1
      after = 1 + cluster.length

      expect(described_class.next(sample, before)).to eq(after)
      expect(described_class.previous(sample, after)).to eq(before)
    end
  end

  def be_valid_encoding
    satisfy(&:valid_encoding?)
  end
end
