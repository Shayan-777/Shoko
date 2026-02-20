# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Dictionary::EntryFormatter do
  let(:entry) do
    Shoko::Core::Models::DictionaryEntry.new(
      word: 'Haus',
      language: 'German',
      senses: ['a house or building'],
      translations: %w[house home],
      score: 0.6,
      importance: 0.8
    )
  end

  let(:result) do
    Shoko::Core::Models::DictionaryResult.new(
      query: 'Haus',
      entries: [entry],
      source_lang: 'de',
      target_lang: 'en',
      search_mode: :grouped
    )
  end

  subject(:formatter) { described_class.new(width: 60) }

  describe '#format_result' do
    it 'formats entries with header and footer' do
      lines = formatter.format_result(result)
      joined = lines.join("\n")

      expect(joined).to include('DE')
      expect(joined).to include('EN')
      expect(joined).to include('Haus')
      expect(joined).to include('→')
      expect(joined).to include('English') # Translation label based on target_lang
    end

    it 'includes result position when entry_index is provided' do
      entry2 = Shoko::Core::Models::DictionaryEntry.new(word: 'Haus2', senses: ['another'])
      multi = Shoko::Core::Models::DictionaryResult.new(
        query: 'Haus',
        entries: [entry, entry2],
        source_lang: 'de',
        target_lang: 'en',
        search_mode: :grouped
      )

      lines = formatter.format_result(multi, entry_index: 1)
      expect(lines.join("\n")).to include('2 of 2')
    end

    it 'formats not found results' do
      empty = Shoko::Core::Models::DictionaryResult.new(query: 'missing', entries: [])
      lines = formatter.format_result(empty)
      expect(lines.join("\n")).to include('No results for')
    end

    it 'formats unavailable results' do
      unavailable = Shoko::Core::Models::DictionaryResult.new(
        query: 'missing',
        entries: [],
        source_lang: 'de',
        target_lang: 'en',
        search_mode: :unavailable
      )
      lines = formatter.format_result(unavailable)
      expect(lines.join("\n")).to include('Dictionary unavailable')
    end

    it 'formats error results' do
      error_result = Shoko::Core::Models::DictionaryResult.new(
        query: 'missing',
        entries: [],
        search_mode: :error
      )
      lines = formatter.format_result(error_result)
      expect(lines.join("\n")).to include('Lookup failed')
    end
  end

  describe '#format_fuzzy_results' do
    it 'formats fuzzy matches' do
      matches = [Shoko::Core::Models::FuzzyMatch.new(word: 'Haus', similarity: 0.8)]
      lines = formatter.format_fuzzy_results(matches, 'Huas')
      joined = lines.join("\n")

      expect(joined).to include('Similar to')
      expect(joined).to include('Haus')
      expect(joined).to include('80%')
    end

    it 'falls back to not found when no matches' do
      lines = formatter.format_fuzzy_results([], 'Huas')
      expect(lines.join("\n")).to include('No results for')
    end
  end
end
