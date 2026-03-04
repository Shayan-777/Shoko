# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Shoko::Adapters::Storage::DictionaryStorageAdapter do
  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  subject(:adapter) { described_class.new }

  describe '#default_databases_path' do
    it 'uses the config-root dictionary directory' do
      expect(adapter.default_databases_path).to end_with('/shoko/dictionary')
    end
  end

  describe '#ensure_databases_path' do
    it 'creates and returns the configured dictionary path' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'dict')

        expect(adapter.ensure_databases_path(path)).to eq(File.expand_path(path))
        expect(File.directory?(path)).to be(true)
      end
    end
  end

  describe '#databases_present?' do
    it 'returns true when sqlite3 files exist in the resolved path' do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(dir)
        FileUtils.touch(File.join(dir, 'en-de.sqlite3'))

        expect(adapter.databases_present?(dir)).to be(true)
      end
    end
  end

  describe '#remove_databases_path' do
    it 'removes the resolved dictionary directory' do
      Dir.mktmpdir do |dir|
        databases_dir = File.join(dir, 'dictionary')
        FileUtils.mkdir_p(databases_dir)
        FileUtils.touch(File.join(databases_dir, 'en-de.sqlite3'))

        adapter.remove_databases_path(databases_dir)

        expect(File.exist?(databases_dir)).to be(false)
      end
    end

    it 'raises on unsafe dictionary path' do
      expect { adapter.remove_databases_path(Dir.home) }.to raise_error(Shoko::StorageError, /unsafe target path/)
    end
  end
end
