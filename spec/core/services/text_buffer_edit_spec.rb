# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Services::TextBufferEdit do
  GRAPHEMES = ["e\u0301", '👩🏽‍💻', '🇩🇪', 'क्', 'a'].freeze

  it 'deletes a whole grapheme before and after the cursor' do
    GRAPHEMES.each do |grapheme|
      text = "a#{grapheme}b"
      after = 1 + grapheme.length

      expect(described_class.backspace_at(text, after)).to eq(['ab', 1])
      expect(described_class.delete_at(text, 1)).to eq(['ab', 1])
    end
  end

  it 'keeps every cursor on a grapheme boundary across generated edit sequences' do
    random = Random.new(20_260_805)

    100.times do
      text = Array.new(random.rand(1..12)) { GRAPHEMES.sample(random: random) }.join
      cursor = Shoko::Core::Services::GraphemeCursor.boundaries(text).sample(random: random)

      25.times do
        operation = %i[insert backspace delete].sample(random: random)
        text, cursor = generated_edit(text, cursor, operation, random)

        expect(Shoko::Core::Services::GraphemeCursor.boundaries(text)).to include(cursor)
        expect(text).to be_valid_encoding
      end
    end
  end

  def generated_edit(text, cursor, operation, random)
    case operation
    when :insert
      described_class.insert_at(text, cursor, GRAPHEMES.sample(random: random), literal: true)
    when :backspace
      described_class.backspace_at(text, cursor)
    when :delete
      described_class.delete_at(text, cursor)
    end
  end
end
