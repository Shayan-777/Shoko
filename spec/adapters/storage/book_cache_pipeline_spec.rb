# frozen_string_literal: true

require 'tmpdir'
require 'spec_helper'

RSpec.describe Shoko::Adapters::Storage::BookCachePipeline do
  class CacheThatFailsWrite
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

    class << self
      def cache_file?(_path)
        false
      end

      def cache_path_for_sha(_sha, cache_root:)
        File.join(cache_root, 'failing.cache')
      end
    end

    attr_reader :cache_path, :source_path

    def initialize(path, cache_root:, logger: nil)
      @source_path = path
      @cache_path = File.join(cache_root, 'failing.cache')
      @logger = logger
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
      'b' * 64
    end
  end

  class FallbackImporter
    def initialize(formatting_service: nil, progress_reporter: nil)
      @formatting_service = formatting_service
      @progress_reporter = progress_reporter
    end

    def import(_path)
      chapter = Shoko::Core::Models::Chapter.new(
        number: '1',
        title: 'Chapter 1',
        lines: ['content'],
        metadata: {},
        blocks: nil,
        raw_content: 'content'
      )

      Shoko::Core::Models::BookData.new(
        title: 'Fallback Book',
        language: 'en',
        authors: ['Author'],
        chapters: [chapter],
        toc_entries: [],
        opf_path: nil,
        spine: [],
        chapter_hrefs: [],
        resources: {},
        metadata: {},
        container_path: nil,
        container_xml: nil,
        chapters_generation: nil,
        format_data: {}
      )
    end
  end

  it 'raises cache load error when cache write fails' do
    Dir.mktmpdir('book-cache-pipeline-spec') do |dir|
      source_path = File.join(dir, 'book.custom')
      File.write(source_path, 'not-used')

      pipeline = described_class.new(
        cache_class: CacheThatFailsWrite,
        cache_root: dir,
        default_importer_class: FallbackImporter
      )

      expect { pipeline.load(source_path) }.to raise_error(Shoko::CacheLoadError, /cache write failed/)
    end
  end

  it 'loads from cache on subsequent source and pointer loads' do
    Dir.mktmpdir('book-cache-pipeline-hit-spec') do |dir|
      source_path = File.join(dir, 'book.custom')
      File.write(source_path, 'source')

      pipeline = described_class.new(
        cache_root: dir,
        default_importer_class: FallbackImporter
      )

      first = pipeline.load(source_path)
      second = pipeline.load(source_path)
      pointer = second.cache_path
      third = pipeline.load(pointer)

      expect(first.loaded_from_cache).to be(false)
      expect(second.loaded_from_cache).to be(true)
      expect(third.loaded_from_cache).to be(true)
      expect(pointer).to end_with('.cache')
    end
  end
end
