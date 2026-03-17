# frozen_string_literal: true

require 'tmpdir'
require 'spec_helper'

RSpec.describe Shoko::Adapters::Storage::BookCachePipeline do
  def build_progress_collector
    Struct.new(:events) do
      def update_status(message: nil, progress: nil)
        events << { message: message, progress: progress }
      end
    end.new([])
  end

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

  it 'warms persistent image cache entries after a successful import' do
    Dir.mktmpdir('book-cache-pipeline-warm-spec') do |dir|
      source_path = File.join(dir, 'book.custom')
      File.write(source_path, 'source')
      warmup = instance_double('ImageCacheWarmup', warm_book_data: nil)

      pipeline = described_class.new(
        cache_root: dir,
        default_importer_class: FallbackImporter,
        image_cache_warmup: warmup
      )

      expect(warmup).to receive(:warm_book_data).with(
        book_data: an_instance_of(Shoko::Core::Models::BookData),
        book_sha: kind_of(String),
        epub_path: source_path
      ).once

      pipeline.load(source_path)
      pipeline.load(source_path)
    end
  end

  it 'maps image warmup progress into the outer cache build progress range' do
    Dir.mktmpdir('book-cache-pipeline-progress-spec') do |dir|
      source_path = File.join(dir, 'book.custom')
      File.write(source_path, 'source')
      collector = build_progress_collector
      warmup = Class.new do
        attr_reader :reporters

        def initialize
          @reporters = []
        end

        def warm_book_data(book_data:, book_sha:, epub_path:, progress_reporter: nil)
          @reporters << { book_data: book_data, book_sha: book_sha, epub_path: epub_path, progress_reporter: progress_reporter }
          progress_reporter&.update_status(message: 'Caching inline images (1/2)...', progress: 0.5)
          :warmed
        end
      end.new
      pipeline = described_class.new(
        cache_root: dir,
        default_importer_class: FallbackImporter,
        progress_reporter: collector,
        image_cache_warmup: warmup
      )

      pipeline.load(source_path)

      expect(warmup.reporters.first[:progress_reporter]).not_to be_nil
      expect(collector.events).to include(
        { message: 'Creating JSON cache...', progress: 0.0 },
        { message: 'Caching inline images...', progress: 0.92 },
        { message: 'Caching inline images (1/2)...', progress: 0.9550000000000001 },
        { message: 'Finalizing cache...', progress: 1.0 }
      )
    end
  end
end
