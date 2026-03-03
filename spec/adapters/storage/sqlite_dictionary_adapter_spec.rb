# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Shoko::Adapters::Storage::SqliteDictionaryAdapter do
  describe '#available_language_pairs' do
    it 'detects language pairs from database files' do
      Dir.mktmpdir do |dir|
        FileUtils.touch(File.join(dir, 'de-en.sqlite3'))
        FileUtils.touch(File.join(dir, 'fr-en.sqlite3'))

        adapter = described_class.new(databases_path: dir)
        pairs = adapter.available_language_pairs

        expect(pairs).to contain_exactly({ source: 'de', target: 'en' }, { source: 'fr', target: 'en' })
      end
    end
  end

  describe '#language_pair_available?' do
    it 'returns true when the database exists' do
      Dir.mktmpdir do |dir|
        FileUtils.touch(File.join(dir, 'de-en.sqlite3'))

        adapter = described_class.new(databases_path: dir)
        expect(adapter.language_pair_available?('de', 'en')).to be(true)
      end
    end

    it 'returns false when the database is missing' do
      Dir.mktmpdir do |dir|
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
      allow(File).to receive(:exist?).and_return(true)
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
