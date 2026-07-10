# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Services::DictionaryService do
  let(:logger) { instance_double(Shoko::Application::Ports::Outbound::Logging, error: nil, debug: nil) }
  let(:repository) { instance_double(Shoko::Application::Ports::Outbound::DictionaryRepository) }
  let(:config_reader) do
    instance_double(Shoko::Application::Ports::Outbound::State::ConfigSnapshot,
                    dictionary_source_lang: 'de',
                    dictionary_target_lang: 'en')
  end
  subject(:service) do
    described_class.new(
      dictionary_repository: repository,
      config_reader: config_reader,
      logger: logger
    )
  end

  describe '#lookup' do
    it 'returns an empty result for blank input' do
      result = service.lookup(' ')
      expect(result.entries).to be_empty
      expect(result.search_mode).to eq(:exact)
    end

    it 'returns unavailable result when repository is nil' do
      no_repo_service = described_class.new(
        dictionary_repository: nil,
        config_reader: config_reader,
        logger: logger
      )

      result = no_repo_service.lookup('Haus')
      expect(result.search_mode).to eq(:unavailable)
    end

    it 'returns unavailable result when language pair is missing' do
      allow(repository).to receive(:language_pair_available?).with('de', 'en').and_return(false)
      result = service.lookup('Haus')
      expect(result.search_mode).to eq(:unavailable)
      expect(result.entries).to be_empty
    end

    it 'builds dictionary entries from repository results' do
      allow(repository).to receive(:language_pair_available?).with('de', 'en').and_return(true)
      allow(repository).to receive(:search).and_return([
                                                         {
                                                           written_rep: 'Haus',
                                                           sense_list: 'house',
                                                           trans_list: 'house',
                                                           score: 0.7,
                                                           importance: 0.4,
                                                         },
                                                       ])

      result = service.lookup('Haus')
      expect(result.entries.length).to eq(1)
      entry = result.entries.first
      expect(entry.word).to eq('Haus')
      expect(entry.senses).to eq(['house'])
      expect(entry.translations).to eq(['house'])
      expect(entry.score).to eq(0.7)
      expect(entry.importance).to eq(0.4)
    end

    it 'passes configured languages to repository search' do
      allow(repository).to receive(:language_pair_available?).with('de', 'en').and_return(true)
      allow(repository).to receive(:search).and_return([])

      service.lookup('  Baum ')
      expect(repository).to have_received(:search).with('Baum',
                                                        source_lang: 'de',
                                                        target_lang: 'en',
                                                        mode: :grouped,
                                                        limit: 15)
    end

    it 'falls back to default languages when config is blank' do
      blank_config = instance_double(Shoko::Application::Ports::Outbound::State::ConfigSnapshot, dictionary_source_lang: nil, dictionary_target_lang: '')
      fallback_service = described_class.new(
        dictionary_repository: repository,
        config_reader: blank_config,
        logger: logger
      )

      allow(repository).to receive(:language_pair_available?).with('de', 'en').and_return(true)
      allow(repository).to receive(:search).and_return([])

      fallback_service.lookup('Haus')
      expect(repository).to have_received(:search).with('Haus',
                                                        source_lang: 'de',
                                                        target_lang: 'en',
                                                        mode: :grouped,
                                                        limit: 15)
    end

    it 'returns typed error result when repository raises a typed failure' do
      allow(repository).to receive(:language_pair_available?).and_return(true)
      allow(repository).to receive(:search).and_raise(
        Shoko::Application::Ports::Outbound::DictionaryRepository::RepositoryError.new(
          code: :invalid_data,
          message: 'broken sqlite payload'
        )
      )

      result = service.lookup('Haus')
      expect(result.search_mode).to eq(:error)
      expect(result.error_message).to eq('Dictionary database is invalid. Reinstall the dictionary file.')
    end
  end

  describe '#fuzzy_search' do
    it 'maps repository matches to FuzzyMatch objects' do
      allow(repository).to receive(:language_pair_available?).with('de', 'en').and_return(true)
      allow(repository).to receive(:fuzzy_search).and_return([{ word: 'Haus', similarity: 0.8 }])

      matches = service.fuzzy_search('Huas')
      expect(matches.length).to eq(1)
      expect(matches.first.word).to eq('Haus')
      expect(matches.first.similarity).to eq(0.8)
    end

    it 'returns empty when repository is missing' do
      no_repo_service = described_class.new(
        dictionary_repository: nil,
        config_reader: config_reader,
        logger: logger
      )
      expect(no_repo_service.fuzzy_search('Haus')).to eq([])
    end

    it 'returns empty when fuzzy search raises a typed repository failure' do
      allow(repository).to receive(:language_pair_available?).with('de', 'en').and_return(true)
      allow(repository).to receive(:fuzzy_search).and_raise(
        Shoko::Application::Ports::Outbound::DictionaryRepository::RepositoryError.new(
          code: :permission_denied,
          message: 'permission denied'
        )
      )

      expect(service.fuzzy_search('Haus')).to eq([])
    end
  end

  describe '#fuzzy_search_translations' do
    it 'maps translation-side repository matches to FuzzyMatch objects' do
      allow(repository).to receive(:language_pair_available?).with('en', 'de').and_return(true)
      allow(repository).to receive(:fuzzy_search_translations).and_return([{ word: 'wirtschaftlich', similarity: 0.91 }])

      matches = service.fuzzy_search_translations('wirtschaffdlich', source_lang: 'en', target_lang: 'de')

      expect(matches.length).to eq(1)
      expect(matches.first.word).to eq('wirtschaftlich')
      expect(matches.first.similarity).to eq(0.91)
    end
  end

  describe '#available?' do
    it 'returns true when repository reports pairs' do
      allow(repository).to receive(:available_language_pairs).and_return([{ source: 'de', target: 'en' }])
      expect(service.available?).to be(true)
    end

    it 'returns false when repository is missing' do
      no_repo_service = described_class.new(
        dictionary_repository: nil,
        config_reader: config_reader,
        logger: logger
      )
      expect(no_repo_service.available?).to be(false)
    end
  end

  describe '#available_language_pairs' do
    it 'returns pairs from repository' do
      allow(repository).to receive(:available_language_pairs).and_return([{ source: 'de', target: 'en' }])
      expect(service.available_language_pairs).to eq([{ source: 'de', target: 'en' }])
    end

    it 'returns empty when repository is missing' do
      no_repo_service = described_class.new(
        dictionary_repository: nil,
        config_reader: config_reader,
        logger: logger
      )
      expect(no_repo_service.available_language_pairs).to eq([])
    end
  end
end
