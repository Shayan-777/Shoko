# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Shoko::Adapters::Storage::DataCleanupAdapter do
  subject(:adapter) { described_class.new }

  describe '#remove_cache_root' do
    it 'removes cache directory when basename is allowed' do
      Dir.mktmpdir do |dir|
        cache_root = File.join(dir, 'shoko')
        FileUtils.mkdir_p(cache_root)
        File.write(File.join(cache_root, 'cache.dat'), 'x')

        adapter.remove_cache_root(cache_root)

        expect(File.exist?(cache_root)).to be(false)
      end
    end

    it 'raises on unsafe cache root path' do
      expect { adapter.remove_cache_root(Dir.home) }.to raise_error(Shoko::StorageError, /unsafe target path|unexpected basename/)
    end
  end

  describe '#remove_downloads_root' do
    it 'removes downloads directory under config root' do
      Dir.mktmpdir do |dir|
        downloads_root = File.join(dir, 'downloads')
        FileUtils.mkdir_p(downloads_root)
        File.write(File.join(downloads_root, 'book.epub'), 'x')

        adapter.remove_downloads_root(dir)

        expect(File.exist?(downloads_root)).to be(false)
      end
    end
  end

  describe '#remove_user_data_files' do
    it 'removes only selected user data files' do
      Dir.mktmpdir do |dir|
        annotations = File.join(dir, 'annotations.json')
        bookmarks = File.join(dir, 'bookmarks.json')
        progress = File.join(dir, 'progress.json')
        config_file = File.join(dir, 'config.json')
        [annotations, bookmarks, progress, config_file].each { |path| File.write(path, '{}') }

        adapter.remove_user_data_files(
          config_root: dir,
          annotations: true,
          bookmarks: false,
          progress: true,
          config_file: false
        )

        expect(File.exist?(annotations)).to be(false)
        expect(File.exist?(bookmarks)).to be(true)
        expect(File.exist?(progress)).to be(false)
        expect(File.exist?(config_file)).to be(true)
      end
    end
  end
end
