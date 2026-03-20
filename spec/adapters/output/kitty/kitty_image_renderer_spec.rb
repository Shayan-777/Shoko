# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Shoko::Adapters::Output::Kitty::KittyImageRenderer do
  let(:resource_loader_class) do
    Struct.new(:cached_entries, :stored_entries, :fetched_entries) do
      def resolve_chapter_relative(chapter_entry_path, src)
        base = File.dirname(chapter_entry_path)
        File.expand_path(File.join('/', base, src), '/').sub(%r{^/}, '')
      end

      def cached?(book_sha:, entry_path:)
        cached_entries.key?([book_sha, entry_path])
      end

      def fetch(book_sha:, epub_path:, entry_path:, persist:, cache_key: nil)
        fetched_entries << {
          book_sha: book_sha,
          epub_path: epub_path,
          entry_path: entry_path,
          cache_key: cache_key,
          persist: persist,
        }
        key = [book_sha, cache_key || entry_path]
        return cached_entries[key] if cached_entries.key?(key)

        cached_entries.fetch([book_sha, entry_path], nil)
      end

      def cache_entry(book_sha:, entry_path:, bytes:)
        stored_entries << { book_sha: book_sha, entry_path: entry_path, bytes: bytes }
        cached_entries[[book_sha, entry_path]] = bytes
      end
    end
  end

  let(:transcoder_class) do
    Struct.new(:result) do
      def to_png(bytes)
        result || bytes
      end
    end
  end

  describe '#hashed_id' do
    it 'returns a non-zero 24-bit id' do
      dummy_loader = Shoko::Adapters::Output::Kitty::ResourceLoader.new(loader: double('EpubResourceLoader'))
      renderer = described_class.new(resource_loader: dummy_loader)
      id = renderer.send(:hashed_id, 'seed')
      expect(id).to be_between(1, 0xFF_FF_FF)
    end
  end

  describe '#warm_cache' do
    let(:png_bytes) { "\x89PNG\r\n\x1a\n#{"\x00" * 16}".b }
    let(:loader) do
      resource_loader_class.new(
        cached_entries: { ['a' * 64, 'OPS/images/cover.jpg'] => 'JPEGDATA' },
        stored_entries: [],
        fetched_entries: []
      )
    end

    it 'creates and persists a png cache entry' do
      Dir.mktmpdir('kitty-image-renderer-spec') do |dir|
        epub_path = File.join(dir, 'book.epub')
        File.write(epub_path, 'epub')

        renderer = described_class.new(
          resource_loader: loader,
          transcoder: transcoder_class.new(png_bytes)
        )

        result = renderer.warm_cache(
          book_sha: 'a' * 64,
          epub_path: epub_path,
          chapter_entry_path: 'OPS/ch1.xhtml',
          src: 'images/cover.jpg'
        )

        expect(result).to eq(:warmed)
        expect(loader.fetched_entries).to include(
          hash_including(entry_path: 'OPS/images/cover.jpg', persist: true, cache_key: nil)
        )
        expect(loader.stored_entries).to include(
          hash_including(entry_path: 'OPS/images/cover.jpg|kitty_png_v1', bytes: png_bytes)
        )
      end
    end

    it 'returns cached when the png cache entry already exists' do
      loader.cached_entries[['a' * 64, 'OPS/images/cover.jpg|kitty_png_v1']] = png_bytes

      Dir.mktmpdir('kitty-image-renderer-spec') do |dir|
        epub_path = File.join(dir, 'book.epub')
        File.write(epub_path, 'epub')

        renderer = described_class.new(
          resource_loader: loader,
          transcoder: transcoder_class.new(png_bytes)
        )

        result = renderer.warm_cache(
          book_sha: 'a' * 64,
          epub_path: epub_path,
          chapter_entry_path: 'OPS/ch1.xhtml',
          src: 'images/cover.jpg'
        )

        expect(result).to eq(:cached)
        expect(loader.stored_entries).to be_empty
      end
    end
  end

  describe '#prepare_virtual' do
    let(:png_bytes) { "\x89PNG\r\n\x1a\n#{"\x00" * 16}".b }

    it 'reuses a prepared virtual placement when the same image reappears' do
      loader = resource_loader_class.new(
        cached_entries: { ['a' * 64, 'OPS/images/cover.jpg|kitty_png_v1'] => png_bytes },
        stored_entries: [],
        fetched_entries: []
      )

      Dir.mktmpdir('kitty-image-renderer-spec') do |dir|
        epub_path = File.join(dir, 'book.epub')
        File.write(epub_path, 'epub')
        output = instance_double('Output', raw: nil)
        renderer = described_class.new(
          resource_loader: loader,
          transcoder: transcoder_class.new(png_bytes)
        )

        expect(Shoko::Adapters::Output::Kitty::KittyGraphics).to receive(:transmit_png).once.and_return(['TX'])
        expect(Shoko::Adapters::Output::Kitty::KittyGraphics).to receive(:virtual_place).once.and_return('VP')

        first = renderer.prepare_virtual(
          output: output,
          book_sha: 'a' * 64,
          epub_path: epub_path,
          chapter_entry_path: 'OPS/ch1.xhtml',
          src: 'images/cover.jpg',
          cols: 10,
          rows: 4,
          placement_id: 123,
          z: -1
        )
        second = renderer.prepare_virtual(
          output: output,
          book_sha: 'a' * 64,
          epub_path: epub_path,
          chapter_entry_path: 'OPS/ch1.xhtml',
          src: 'images/cover.jpg',
          cols: 10,
          rows: 4,
          placement_id: 123,
          z: -1
        )

        expect(first).to eq(second)
        expect(output).to have_received(:raw).with('TX').once
        expect(output).to have_received(:raw).with('VP').once
      end
    end

    it 'can reset placement caching for a new reader session without retransmitting the image data' do
      loader = resource_loader_class.new(
        cached_entries: { ['a' * 64, 'OPS/images/cover.jpg|kitty_png_v1'] => png_bytes },
        stored_entries: [],
        fetched_entries: []
      )

      Dir.mktmpdir('kitty-image-renderer-spec') do |dir|
        epub_path = File.join(dir, 'book.epub')
        File.write(epub_path, 'epub')
        output = instance_double('Output', raw: nil)
        renderer = described_class.new(
          resource_loader: loader,
          transcoder: transcoder_class.new(png_bytes)
        )

        expect(Shoko::Adapters::Output::Kitty::KittyGraphics).to receive(:transmit_png).once.and_return(['TX'])
        expect(Shoko::Adapters::Output::Kitty::KittyGraphics).to receive(:virtual_place).twice.and_return('VP')

        renderer.prepare_virtual(
          output: output,
          book_sha: 'a' * 64,
          epub_path: epub_path,
          chapter_entry_path: 'OPS/ch1.xhtml',
          src: 'images/cover.jpg',
          cols: 10,
          rows: 4,
          placement_id: 123,
          z: -1
        )
        renderer.reset_virtual_placements!
        renderer.prepare_virtual(
          output: output,
          book_sha: 'a' * 64,
          epub_path: epub_path,
          chapter_entry_path: 'OPS/ch1.xhtml',
          src: 'images/cover.jpg',
          cols: 10,
          rows: 4,
          placement_id: 123,
          z: -1
        )

        expect(output).to have_received(:raw).with('TX').once
        expect(output).to have_received(:raw).with('VP').twice
      end
    end
  end
end
