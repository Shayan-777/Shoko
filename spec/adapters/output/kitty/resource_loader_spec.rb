# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Kitty::ResourceLoader do
  let(:loader_class) do
    Class.new do
      class << self
        def resolve_chapter_relative(chapter_entry_path, src)
          "#{chapter_entry_path}|#{src}"
        end
      end

      attr_reader :fetch_calls

      def initialize
        @fetch_calls = []
      end

      def fetch(**kwargs)
        @fetch_calls << kwargs
        'bytes'
      end

      def cache_entry(**); end

      def cached?(**)
        false
      end
    end
  end

  it 'passes through fetch without requiring cache_key' do
    loader = loader_class.new
    resource_loader = described_class.new(loader: loader)

    result = resource_loader.fetch(
      book_sha: 'a' * 64,
      epub_path: '/tmp/book.epub',
      entry_path: 'OPS/images/a.jpg',
      persist: true
    )

    expect(result).to eq('bytes')
    expect(loader.fetch_calls).to eq(
      [
        {
          book_sha: 'a' * 64,
          epub_path: '/tmp/book.epub',
          entry_path: 'OPS/images/a.jpg',
          cache_key: nil,
          persist: true,
        },
      ]
    )
  end

  describe 'Kindle image sources (PDB records, not a zip)' do
    let(:store) { {} }

    # Blob cache backed by a shared hash, keyed by entry_path (as the real
    # EpubResourceLoader caches by cache_key || entry_path).
    let(:caching_loader) do
      store_ref = store
      Class.new do
        define_singleton_method(:resolve_chapter_relative) { |_chapter, src| src }
        define_method(:fetch) { |entry_path:, **| store_ref[entry_path] }
        define_method(:cache_entry) { |entry_path:, bytes:, **| store_ref[entry_path] = bytes }
        define_method(:cached?) { |entry_path:, **| store_ref.key?(entry_path) }
      end.new
    end

    let(:kindle_source) do
      Class.new do
        def fetch(_path, entry_path)
          entry_path == 'image0001.jpg' ? 'JPEG-SOURCE-BYTES' : nil
        end
      end.new
    end

    subject(:resource_loader) { described_class.new(loader: caching_loader, kindle_image_source: kindle_source) }

    it 'extracts the source image from the container and caches it on first fetch' do
      result = resource_loader.fetch(book_sha: 'b' * 64, epub_path: '/books/x.azw3',
                                     entry_path: 'image0001.jpg', persist: true)

      expect(result).to eq('JPEG-SOURCE-BYTES')
      expect(store['image0001.jpg']).to eq('JPEG-SOURCE-BYTES')
    end

    # Regression: a transcoded-PNG lookup (cache_key) must return the PNG, not
    # the raw source image — otherwise the terminal gets a JPEG where it expects
    # a PNG and renders nothing.
    it 'honors cache_key so a PNG lookup returns the PNG, not the source' do
      store['image0001.jpg'] = 'JPEG-SOURCE-BYTES'
      store['image0001.jpg|kitty_png_v1'] = 'PNG-BYTES'

      result = resource_loader.fetch(book_sha: 'b' * 64, epub_path: '/books/x.azw3',
                                     entry_path: 'image0001.jpg',
                                     cache_key: 'image0001.jpg|kitty_png_v1', persist: false)

      expect(result).to eq('PNG-BYTES')
    end

    it 'returns nil for an image the container does not contain' do
      result = resource_loader.fetch(book_sha: 'b' * 64, epub_path: '/books/x.azw3',
                                     entry_path: 'image9999.jpg', persist: true)
      expect(result).to be_nil
    end
  end
end
