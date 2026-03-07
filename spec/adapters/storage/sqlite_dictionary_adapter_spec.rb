# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Shoko::Adapters::Storage::SqliteDictionaryAdapter do
  def write_sqlite_header(path)
    File.binwrite(path, "SQLite format 3\0")
  end

  describe '#available_language_pairs' do
    it 'detects language pairs from valid database files' do
      Dir.mktmpdir do |dir|
        write_sqlite_header(File.join(dir, 'de-en.sqlite3'))
        File.binwrite(File.join(dir, 'fr-en.sqlite3'), '')

        adapter = described_class.new(databases_path: dir)
        pairs = adapter.available_language_pairs

        expect(pairs).to contain_exactly({ source: 'de', target: 'en' })
      end
    end
  end

  describe '#language_pair_available?' do
    it 'returns true when the database file looks valid' do
      Dir.mktmpdir do |dir|
        write_sqlite_header(File.join(dir, 'de-en.sqlite3'))

        adapter = described_class.new(databases_path: dir)
        expect(adapter.language_pair_available?('de', 'en')).to be(true)
      end
    end

    it 'returns false when the database is missing or empty' do
      Dir.mktmpdir do |dir|
        File.binwrite(File.join(dir, 'de-en.sqlite3'), '')
        adapter = described_class.new(databases_path: dir)
        expect(adapter.language_pair_available?('de', 'en')).to be(false)
      end
    end
  end

  describe '#database_path_for' do
    it 'normalizes language names to codes' do
      Dir.mktmpdir do |dir|
        adapter = described_class.new(databases_path: dir)
        path = adapter.database_path_for('German', 'English')
        expect(path).to end_with('de-en.sqlite3')
      end
    end
  end

  describe '#search' do
    it 'returns empty results when database is missing' do
      Dir.mktmpdir do |dir|
        adapter = described_class.new(databases_path: dir)
        expect(adapter).not_to receive(:require_sqlite3!)

        results = adapter.search('Haus', source_lang: 'de', target_lang: 'en')
        expect(results).to eq([])
      end
    end

    it 'raises a typed repository error when sqlite encounters a database error' do
      sqlite_module = Module.new
      stub_const('SQLite3', sqlite_module)
      sqlite_module.const_set(:Exception, Class.new(StandardError))
      sqlite_module.const_set(:Database, Class.new)

      adapter = described_class.new(databases_path: '/tmp')
      allow(adapter).to receive(:database_path_for).and_return('/tmp/fake.sqlite3')
      allow(adapter).to receive(:valid_database_file?).with('/tmp/fake.sqlite3').and_return(true)
      allow(adapter).to receive(:require_sqlite3!)
      fake_db = double('SQLite3::Database', close: nil)
      allow(fake_db).to receive(:results_as_hash=)
      allow(SQLite3::Database).to receive(:new).and_return(fake_db)
      allow(fake_db).to receive(:execute).and_raise(SQLite3::Exception, 'database disk image is malformed')

      expect do
        adapter.search('Haus', source_lang: 'de', target_lang: 'en')
      end.to raise_error(Shoko::Core::Ports::Outbound::DictionaryRepository::RepositoryError) do |error|
        expect(error.code).to eq(:corrupt_data)
        expect(error.details[:path]).to eq('/tmp/fake.sqlite3')
        expect(error.message).to include('database disk image is malformed')
      end
    end

    it 'returns empty results for blank fuzzy queries before touching storage' do
      adapter = described_class.new(databases_path: '/tmp')
      expect(adapter).not_to receive(:database_path_for)

      results = adapter.search(" \n\t", source_lang: 'de', target_lang: 'en', mode: :fuzzy)
      expect(results).to eq([])
    end
  end

  describe '#fuzzy_search' do
    it 'returns empty results for blank fuzzy queries before touching storage' do
      adapter = described_class.new(databases_path: '/tmp')
      expect(adapter).not_to receive(:database_path_for)

      results = adapter.fuzzy_search(" \n\t", source_lang: 'de', target_lang: 'en')
      expect(results).to eq([])
    end
  end

  describe 'fuzzy ranking internals' do
    it 'keeps fuzzy ranking deterministic while prioritizing closer matches' do
      adapter = described_class.new(databases_path: '/tmp')
      candidates = [
        { 'written_rep' => 'haus', 'max_score' => 120, 'rel_importance' => 0.8 },
        { 'written_rep' => 'hause', 'max_score' => 80, 'rel_importance' => 0.3 },
        { 'written_rep' => 'haas', 'max_score' => 60, 'rel_importance' => 0.1 },
        { 'written_rep' => 'hans', 'max_score' => 75, 'rel_importance' => 0.2 },
        { 'written_rep' => 'hess', 'max_score' => 40, 'rel_importance' => 0.05 },
        { 'written_rep' => 'horse', 'max_score' => 150, 'rel_importance' => 0.9 },
      ]

      scored = adapter.send(:score_candidates, 'haus', candidates, similarity_threshold: 0.4)
      ranked = adapter.send(:filter_and_sort_fuzzy, scored, 10, similarity_threshold: 0.4)

      expect(ranked.map { |row| row[:word] }).to eq(%w[haus hause hans haas])
      expect(ranked.map { |row| row[:word] }).not_to include('horse')
      expect(ranked.each_cons(2).all? { |left, right| left[:similarity] >= right[:similarity] }).to be(true)
    end

    it 'prioritizes close common-word matches over capitalized proper-noun noise' do
      adapter = described_class.new(databases_path: '/tmp')
      candidates = [
        { 'written_rep' => 'ambiguous', 'max_score' => 128.5, 'rel_importance' => 0.767374363921945 },
        { 'written_rep' => 'Adige', 'max_score' => 104, 'rel_importance' => 0.386544833650426 },
        { 'written_rep' => 'Agnes', 'max_score' => 152.0, 'rel_importance' => 0.375979816929025 },
        { 'written_rep' => 'Aigen', 'max_score' => 4, 'rel_importance' => 0.000333812491529793 },
        { 'written_rep' => 'Abitur', 'max_score' => 100, 'rel_importance' => 0.225101706973851 },
      ]

      scored = adapter.send(:score_candidates, 'ambigues', candidates, similarity_threshold: 0.4)
      ranked = adapter.send(:filter_and_sort_fuzzy, scored, 10, similarity_threshold: 0.4)

      expect(ranked.first[:word]).to eq('ambiguous')
      expect(ranked.map { |row| row[:word] }).not_to include('Adige')
      expect(ranked.map { |row| row[:word] }).not_to include('Agnes')
    end

    it 'extracts single-word translation tokens for reverse-direction spell suggestions' do
      adapter = described_class.new(databases_path: '/tmp')
      row = {
        'trans_list' => 'sparsam | wirtschaftlich | Asiatisch-pazifische wirtschaftliche Zusammenarbeit',
        'max_score' => 101.0,
        'rel_importance' => 0.42,
      }

      candidates = adapter.send(:translation_candidates_from_row, row, word: 'wirtschaffdlich', min_len: 5, max_len: 18)

      expect(candidates.map { |candidate| candidate['written_rep'] }).to include('wirtschaftlich')
      expect(candidates.map { |candidate| candidate['written_rep'] }).to include('wirtschaftliche')
      expect(candidates.map { |candidate| candidate['written_rep'] }).not_to include('Zusammenarbeit')
    end

    it 'computes exact Levenshtein distance in normal mode and short-circuits in bounded mode' do
      adapter = described_class.new(databases_path: '/tmp')

      expect(adapter.send(:levenshtein_distance, 'kitten', 'sitting')).to eq(3)
      expect(adapter.send(:levenshtein_distance, 'abcdefghij', 'a', max_distance: 2)).to eq(3)
      expect(adapter.send(:levenshtein_distance, 'abcdef', 'azced', max_distance: 1)).to eq(2)
    end
  end

  describe '#require_sqlite3!' do
    it 'raises a typed unavailable error when sqlite3 is unavailable' do
      adapter = described_class.new
      allow(Shoko::Shared::OptionalDependency).to receive(:require_gem!).with('sqlite3').and_raise(
        Shoko::DependencyUnavailableError,
        "Required optional gem 'sqlite3' is not installed"
      )

      expect do
        adapter.send(:require_sqlite3!)
      end.to raise_error(Shoko::DependencyUnavailableError) do |error|
        expect(error.message).to include("optional gem 'sqlite3'")
      end
    end
  end
end
