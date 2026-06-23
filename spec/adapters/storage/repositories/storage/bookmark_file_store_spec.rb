# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'json'

RSpec.describe Shoko::Adapters::Storage::Repositories::Storage::BookmarkFileStore do
  let(:file_writer) do
    writer = Object.new
    writer.define_singleton_method(:write) do |path, data|
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, data)
      true
    end
    writer
  end

  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  def store_path
    File.join(ENV.fetch('XDG_CONFIG_HOME'), 'shoko', 'bookmarks.json')
  end

  it 'round-trips bookmarks through a versioned envelope' do
    store = described_class.new(file_writer: file_writer)
    store.add(Shoko::Core::Models::BookmarkData.new('book.epub', 1, 4, 'hi'))

    raw = JSON.parse(File.read(store_path))
    expect(raw['schema_version']).to eq(1)
    expect(raw['entries']).to have_key('book.epub')

    reread = described_class.new(file_writer: file_writer).get('book.epub')
    expect(reread.map(&:text_snippet)).to eq(['hi'])
  end

  it 'reads a pre-versioning bare-hash file' do
    FileUtils.mkdir_p(File.dirname(store_path))
    File.write(
      store_path,
      JSON.generate(
        'book.epub' => [
          { 'chapter' => 1, 'line_offset' => 4, 'text' => 'legacy', 'timestamp' => '2026-01-01T00:00:00Z' },
        ]
      )
    )
    store = described_class.new(file_writer: file_writer)

    expect(store.get('book.epub').map(&:text_snippet)).to eq(['legacy'])
  end
end
