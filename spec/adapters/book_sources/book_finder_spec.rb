# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'spec_helper'
require 'time'
require 'shoko/adapters/book_sources/book_finder'
require 'shoko/adapters/storage/atomic_file_writer'

RSpec.describe Shoko::Adapters::BookSources::BookFinder do
  class BookFinderSpecProbe
    def book_file?(path)
      path.end_with?('.epub')
    end
  end

  def build_finder(config_root)
    described_class.new(
      cache_writer: Shoko::Adapters::Storage::AtomicFileWriter,
      config_root: config_root,
      book_file_probe: BookFinderSpecProbe.new
    )
  end

  around do |example|
    Dir.mktmpdir('shoko-book-finder-spec') do |root|
      @root = root
      @home = File.join(root, 'home')
      @config_root = File.join(root, 'config')
      @scan_root = File.join(root, 'books')
      FileUtils.mkdir_p([@home, @config_root, @scan_root])

      with_env('HOME' => @home, 'SHOKO_BOOK_SCAN_DIRS' => @scan_root) { example.run }
    end
  end

  it 'writes cache payloads with a defined version' do
    File.write(File.join(@scan_root, 'Book.epub'), 'book')
    finder = build_finder(@config_root)

    files = finder.scan_system(force_refresh: true)
    payload = JSON.parse(File.read(finder.cache_file))

    expect(files.length).to eq(1)
    expect(payload['version']).to eq(described_class::VERSION)
    expect(payload['files'].first['name']).to eq('Book')
  end

  it 'treats corrupt JSON cache entries as misses and removes them' do
    finder = build_finder(@config_root)
    File.write(finder.cache_file, '{')

    expect(finder.load_cached_files(allow_expired: true)).to eq([])
    expect(File.exist?(finder.cache_file)).to be(false)
  end

  it 'can return stale cache entries for immediate startup rendering' do
    finder = build_finder(@config_root)
    cached_files = [{ 'path' => '/books/old.epub', 'name' => 'Old' }]
    File.write(
      finder.cache_file,
      JSON.generate('timestamp' => '2000-01-01T00:00:00Z', 'files' => cached_files, 'version' => 1)
    )

    expect(finder.load_cached_files(allow_expired: true)).to eq(cached_files)
    expect(finder.load_cached_files(allow_expired: false)).to eq([])
  end

  it 'does not crash on malformed cache timestamps' do
    finder = build_finder(@config_root)
    File.write(
      finder.cache_file,
      JSON.generate('timestamp' => 'not-a-time', 'files' => [{ 'path' => '/books/bad.epub' }], 'version' => 1)
    )

    expect { finder.scan_system(force_refresh: false) }.not_to raise_error
  end

  it 'keeps partial scan results when a scan times out' do
    finder = build_finder(@config_root)
    partial = [{ 'path' => '/books/partial.epub', 'name' => 'Partial' }]
    allow(finder).to receive(:perform_scan) do |epubs|
      epubs.concat(partial)
      raise Timeout::Error
    end

    expect(finder.scan_system(force_refresh: true)).to eq(partial)
    expect(JSON.parse(File.read(finder.cache_file))['files']).to eq(partial)
  end

  it 'does not overwrite an existing cache when an unexpected scan error escapes' do
    finder = build_finder(@config_root)
    cached_files = [{ 'path' => '/books/cached.epub', 'name' => 'Cached' }]
    File.write(
      finder.cache_file,
      JSON.generate('timestamp' => Time.now.iso8601, 'files' => cached_files, 'version' => 1)
    )
    allow(finder).to receive(:perform_scan).and_raise(StandardError, 'boom')

    expect { finder.scan_system(force_refresh: true) }.to raise_error(StandardError, 'boom')
    expect(JSON.parse(File.read(finder.cache_file))['files']).to eq(cached_files)
  end
end
