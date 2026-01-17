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

    it 'raises when sqlite encounters a database error' do
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
      end.to raise_error(SQLite3::Exception)
    end
  end

  describe '#require_sqlite3!' do
    it 'raises a helpful error when sqlite3 is unavailable' do
      adapter = described_class.new
      allow(Kernel).to receive(:require).and_call_original
      allow(Kernel).to receive(:require).with('sqlite3').and_raise(LoadError)
      allow(Shoko::Shared::OptionalDependency).to receive(:add_gem_load_path).with('sqlite3').and_return(nil)

      expect { adapter.send(:require_sqlite3!) }.to raise_error(LoadError, /optional gem 'sqlite3'/)
    end
  end
end
