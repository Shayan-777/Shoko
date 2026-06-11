# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Shoko::Adapters::Storage::JsonCacheStore do
  it 'writes and reads cached payloads' do
    Dir.mktmpdir do |dir|
      source = Tempfile.new('book')
      source.write('sample')
      source.flush

      store = described_class.new(cache_root: dir)
      sha = 'a' * 64
      chapters = [{ position: 0, raw_content: '<p>hi</p>', title: 'One' }]
      resources = [{ path: 'image.png', data: 'PNG' }]
      layouts = { 'default' => { 'lines' => [1, 2, 3] } }

      written = store.write_payload(
        sha: sha,
        source_path: source.path,
        source_mtime: File.mtime(source.path),
        generated_at: Time.now,
        serialized_book: { title: 'Test' },
        serialized_chapters: chapters,
        serialized_resources: resources,
        serialized_layouts: layouts
      )

      expect(written).to be(true)

      payload = store.fetch_payload(sha, include_resources: true)
      expect(payload).not_to be_nil
      expect(payload.metadata_row['source_sha']).to eq(sha)
      expect(payload.chapters.first['position']).to eq(0)
      expect(payload.resources.first[:path]).to eq('image.png')
      expect(payload.layouts['default']).to eq('lines' => [1, 2, 3])

      manifest = store.list_books
      expect(manifest.first['source_sha']).to eq(sha)
    ensure
      source.close!
    end
  end

  it 'mutates layouts in place' do
    Dir.mktmpdir do |dir|
      store = described_class.new(cache_root: dir)
      sha = 'b' * 64

      store.write_payload(
        sha: sha,
        source_path: __FILE__,
        source_mtime: File.mtime(__FILE__),
        generated_at: Time.now,
        serialized_book: { title: 'Layouts' },
        serialized_chapters: [],
        serialized_resources: [],
        serialized_layouts: { 'layout' => { 'foo' => 'bar' } }
      )

      store.mutate_layouts(sha) do |layouts|
        layouts['layout'] = { 'foo' => 'baz' }
      end

      expect(store.load_layout(sha, 'layout')).to eq('foo' => 'baz')
    end
  end

  describe 'corrupt cache files degrade instead of crashing' do
    def populate(store, sha, layouts: {})
      store.write_payload(
        sha: sha,
        source_path: __FILE__,
        source_mtime: File.mtime(__FILE__),
        generated_at: Time.now,
        serialized_book: { title: 'Corrupt' },
        serialized_chapters: [],
        serialized_resources: [],
        serialized_layouts: layouts
      )
    end

    it 'returns nil from fetch_payload when the payload file is corrupt JSON' do
      Dir.mktmpdir do |dir|
        store = described_class.new(cache_root: dir)
        sha = 'b' * 64
        populate(store, sha)
        payload_path = Dir[File.join(dir, '**', '*.json')].find { |p| File.basename(p) != 'manifest.json' }
        File.binwrite(payload_path, '{ this is not valid json')

        result = nil
        expect { result = store.fetch_payload(sha) }.not_to raise_error
        expect(result).to be_nil
      end
    end

    it 'returns nil from load_layout when the layout file is corrupt JSON' do
      Dir.mktmpdir do |dir|
        store = described_class.new(cache_root: dir)
        sha = 'c' * 64
        populate(store, sha, layouts: { 'layout' => { 'foo' => 'bar' } })
        layout_path = Dir[File.join(dir, 'layouts', '**', '*.json')].first
        File.binwrite(layout_path, "\x00\xFFnot json".b)

        layout = :unset
        expect { layout = store.load_layout(sha, 'layout') }.not_to raise_error
        expect(layout).to be_nil
      end
    end

    it 'lists an empty library when the manifest file is corrupt' do
      Dir.mktmpdir do |dir|
        store = described_class.new(cache_root: dir)
        File.binwrite(File.join(dir, 'manifest.json'), 'not-an-array')

        rows = nil
        expect { rows = store.list_books }.not_to raise_error
        expect(rows).to eq([])
      end
    end
  end
end
