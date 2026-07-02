# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'json'

RSpec.describe Shoko::Adapters::Storage::Repositories::Storage::ProgressFileStore do
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
    File.join(ENV.fetch('XDG_CONFIG_HOME'), 'shoko', 'progress.json')
  end

  it 'round-trips progress through a versioned envelope' do
    store = described_class.new(file_writer: file_writer)
    store.save('book.epub', 3, 12)

    raw = JSON.parse(File.read(store_path))
    expect(raw['schema_version']).to eq(1)
    expect(raw['entries']['book.epub']).to include('chapter' => 3, 'line_offset' => 12)

    reloaded = described_class.new(file_writer: file_writer).load('book.epub')
    expect(reloaded).to include('chapter' => 3, 'line_offset' => 12)
  end

  it 'round-trips the optional position anchor and omits it when absent' do
    store = described_class.new(file_writer: file_writer)
    anchor = { 'quote' => 'It was the best of times', 'position' => 0.25 }

    store.save('anchored.epub', 3, 12, anchor)
    store.save('plain.epub', 1, 5)

    expect(store.load('anchored.epub')).to include('anchor' => anchor)
    expect(store.load('plain.epub')).not_to have_key('anchor')
  end

  it 'reads a pre-versioning bare-hash file' do
    FileUtils.mkdir_p(File.dirname(store_path))
    File.write(
      store_path,
      JSON.generate('book.epub' => { 'chapter' => 2, 'line_offset' => 5, 'timestamp' => '2026-01-01T00:00:00Z' })
    )
    store = described_class.new(file_writer: file_writer)

    expect(store.load('book.epub')).to include('chapter' => 2, 'line_offset' => 5)
  end
end
