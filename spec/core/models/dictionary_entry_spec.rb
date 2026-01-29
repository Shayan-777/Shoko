# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Models::DictionaryEntry do
  describe '.from_hash' do
    it 'builds an entry from hash values' do
      entry = described_class.from_hash(
        written_rep: 'Haus',
        language: 'German',
        lexentry: 'noun',
        sense_list: 'house|building',
        trans_list: 'house|home',
        score: 0.7,
        importance: 0.4
      )

      expect(entry.word).to eq('Haus')
      expect(entry.language).to eq('German')
      expect(entry.lexentry).to eq('noun')
      expect(entry.senses).to eq(%w[house building])
      expect(entry.translations).to eq(%w[house home])
      expect(entry.score).to eq(0.7)
      expect(entry.importance).to eq(0.4)
    end

    it 'falls back to word key and handles arrays' do
      entry = described_class.from_hash(
        word: 'Baum',
        sense: ['tree'],
        translations: %w[tree wood]
      )

      expect(entry.word).to eq('Baum')
      expect(entry.senses).to eq(['tree'])
      expect(entry.translations).to eq(%w[tree wood])
    end
  end

  describe '#to_h' do
    it 'serializes to a hash of attributes' do
      entry = described_class.new(word: 'Haus', senses: ['house'], translations: ['home'])
      expect(entry.to_h).to include(word: 'Haus', senses: ['house'], translations: ['home'])
    end
  end

  describe '#empty?' do
    it 'returns true when there are no senses or translations' do
      entry = described_class.new(word: 'Haus')
      expect(entry).to be_empty
    end

    it 'returns false when senses exist' do
      entry = described_class.new(word: 'Haus', senses: ['house'])
      expect(entry).not_to be_empty
    end
  end

  describe '#senses_grouped' do
    it 'groups senses by inferred part of speech' do
      entry = described_class.new(word: 'test', senses: ['noun a thing', 'verb to test', 'adjective ready'])
      grouped = entry.senses_grouped

      expect(grouped.keys).to contain_exactly('Noun', 'Verb', 'Adjective')
      expect(grouped['Noun']).to include('noun a thing')
      expect(grouped['Verb']).to include('verb to test')
      expect(grouped['Adjective']).to include('adjective ready')
    end
  end
end

RSpec.describe Shoko::Core::Models::DictionaryResult do
  let(:entry) { Shoko::Core::Models::DictionaryEntry.new(word: 'Haus', senses: ['house']) }

  it 'reports found results when entries are present' do
    result = described_class.new(query: 'Haus', entries: [entry])
    expect(result).to be_found
    expect(result.entry_count).to eq(1)
  end

  it 'reports empty when entries are missing or empty' do
    empty_entry = Shoko::Core::Models::DictionaryEntry.new(word: 'x')
    result = described_class.new(query: 'x', entries: [empty_entry])
    expect(result).to be_empty
  end
end

RSpec.describe Shoko::Core::Models::FuzzyMatch do
  it 'classifies confidence based on similarity' do
    high = described_class.new(word: 'Haus', similarity: 0.9)
    medium = described_class.new(word: 'Haus', similarity: 0.7)
    low = described_class.new(word: 'Haus', similarity: 0.4)

    expect(high).to be_high_confidence
    expect(medium).to be_medium_confidence
    expect(low).to be_low_confidence
  end
end
