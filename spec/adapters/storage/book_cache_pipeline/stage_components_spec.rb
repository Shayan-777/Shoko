# frozen_string_literal: true

require 'tmpdir'
require 'spec_helper'

RSpec.describe Shoko::Adapters::Storage::BookCachePipeline do
  let(:fingerprint_filter_class) { described_class.send(:const_get, :FingerprintFilter) }
  let(:manifest_sha_finder_class) { described_class.send(:const_get, :ManifestShaFinder) }
  let(:pointer_cache_cleaner_class) { described_class.send(:const_get, :PointerCacheCleaner) }
  let(:pointer_rebuilder_class) { described_class.send(:const_get, :PointerRebuilder) }
  let(:cache_session_class) { described_class.send(:const_get, :CacheSession) }

  describe 'FingerprintFilter' do
    it 'drops fingerprinted rows when computed fingerprint is blank' do
      row = instance_double('Row', fingerprint_value: 'abcdef')
      filter = fingerprint_filter_class.new('/tmp/book.epub')

      allow(Shoko::Shared::SourceFingerprint).to receive(:compute).and_return('')

      matches, applied, blank = filter.call([row])

      expect(applied).to be(true)
      expect(blank).to be(true)
      expect(matches).to eq([])
    end
  end

  describe 'ManifestShaFinder' do
    let(:source_path) { '/tmp/book.epub' }
    let(:source_mtime) { Time.at(1_700_000_000.0) }
    let(:source_size) { 1234 }

    it 'returns the same SHA with fast scan on and off' do
      rows = [
        {
          'source_path' => source_path,
          'source_mtime' => source_mtime.to_f,
          'source_size_bytes' => source_size,
          'source_fingerprint' => nil,
          'updated_at' => 10.0,
          'source_sha' => 'a' * 64,
        },
        {
          'source_path' => source_path,
          'source_mtime' => source_mtime.to_f,
          'source_size_bytes' => source_size,
          'source_fingerprint' => 'fp-1',
          'updated_at' => 20.0,
          'source_sha' => 'b' * 64,
        },
      ]

      allow(Shoko::Shared::SourceFingerprint).to receive(:compute).with(source_path).and_return('fp-1')

      legacy = manifest_sha_finder_class.with_fast_scan(enabled: false) do
        manifest_sha_finder_class.new(
          rows: rows,
          source_path: source_path,
          source_mtime: source_mtime,
          source_size_bytes: source_size
        ).sha
      end
      fast = manifest_sha_finder_class.with_fast_scan(enabled: true) do
        manifest_sha_finder_class.new(
          rows: rows,
          source_path: source_path,
          source_mtime: source_mtime,
          source_size_bytes: source_size
        ).sha
      end

      expect(fast).to eq(legacy)
      expect(fast).to eq('b' * 64)
    end

    it 'returns nil when fingerprint is required but computed fingerprint is blank' do
      rows = [
        {
          'source_path' => source_path,
          'source_mtime' => source_mtime.to_f,
          'source_size_bytes' => source_size,
          'source_fingerprint' => 'fp-required',
          'updated_at' => 30.0,
          'source_sha' => 'c' * 64,
        },
        {
          'source_path' => source_path,
          'source_mtime' => source_mtime.to_f,
          'source_size_bytes' => source_size,
          'source_fingerprint' => nil,
          'updated_at' => 40.0,
          'source_sha' => 'd' * 64,
        },
      ]

      allow(Shoko::Shared::SourceFingerprint).to receive(:compute).with(source_path).and_return('')

      legacy = manifest_sha_finder_class.with_fast_scan(enabled: false) do
        manifest_sha_finder_class.new(
          rows: rows,
          source_path: source_path,
          source_mtime: source_mtime,
          source_size_bytes: source_size
        ).sha
      end
      fast = manifest_sha_finder_class.with_fast_scan(enabled: true) do
        manifest_sha_finder_class.new(
          rows: rows,
          source_path: source_path,
          source_mtime: source_mtime,
          source_size_bytes: source_size
        ).sha
      end

      expect(legacy).to be_nil
      expect(fast).to be_nil
    end
  end

  describe 'PointerRebuilder' do
    class PointerCacheStub
      class << self
        def cache_file?(path)
          path.end_with?('.cache')
        end
      end

      attr_reader :source_path, :cache_path

      def initialize(source_path:, cache_path:)
        @source_path = source_path
        @cache_path = cache_path
      end
    end

    it 'returns nil when pointer source is not a valid source file' do
      cache = PointerCacheStub.new(source_path: '/tmp/book.cache', cache_path: '/tmp/book.cache')
      rebuilder = pointer_rebuilder_class.new(
        cache: cache,
        formatting_service: nil,
        load_callback: ->(*) { raise 'load callback should not run' }
      )

      expect(rebuilder.call).to be_nil
    end
  end

  describe 'PointerCacheCleaner' do
    it 'removes stale pointer cache file when rebuilt path changes' do
      Dir.mktmpdir('pointer-cache-cleaner-spec') do |dir|
        stale = File.join(dir, 'old.cache')
        rebuilt = File.join(dir, 'new.cache')
        File.write(stale, 'stale')

        pointer_cache_cleaner_class.new(stale, rebuilt).call

        expect(File.exist?(stale)).to be(false)
      end
    end
  end

  describe 'CacheSession fallback payload' do
    class CacheSessionFailingWriteCache
      CACHE_VERSION = 4
      CachePayload = Struct.new(
        :version,
        :source_sha256,
        :source_path,
        :source_mtime,
        :generated_at,
        :book,
        :layouts,
        keyword_init: true
      )

      attr_reader :source_path, :cache_path

      def initialize(source_path:, cache_path:)
        @source_path = source_path
        @cache_path = cache_path
      end

      def cache_file?
        false
      end

      def load_for_source(strict: false)
        nil
      end

      def read_cache(strict: false)
        nil
      end

      def write_book!(_book_data)
        nil
      end

      def sha256
        'f' * 64
      end
    end

    class CacheSessionFallbackImporter
      def initialize(formatting_service: nil, progress_reporter: nil)
        @formatting_service = formatting_service
        @progress_reporter = progress_reporter
      end

      def import(_path)
        Struct.new(:chapters).new([Struct.new(:number).new('1')])
      end
    end

    it 'returns in-memory payload when import succeeds but cache payload cannot be read back' do
      Dir.mktmpdir('cache-session-fallback-spec') do |dir|
        source_path = File.join(dir, 'book.custom')
        cache_path = File.join(dir, 'book.custom.cache')
        File.write(source_path, 'content')
        cache = CacheSessionFailingWriteCache.new(source_path: source_path, cache_path: cache_path)

        session = cache_session_class.new(
          cache: cache,
          formatting_service: nil,
          importer_class: CacheSessionFallbackImporter,
          load_callback: ->(_path, formatting_service: nil) { nil }
        )

        result = session.load

        expect(result).not_to be_nil
        expect(result.loaded_from_cache).to be(false)
        expect(result.source_path).to eq(source_path)
        expect(result.payload.source_path).to eq(source_path)
      end
    end
  end
end
