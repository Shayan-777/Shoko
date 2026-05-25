# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'tmpdir'
require 'spec_helper'

RSpec.describe Shoko::Adapters::Storage::Repositories::DisplayMetadataCacheRepository do
  around do |example|
    Dir.mktmpdir { |dir| @tmpdir = dir; example.run }
  end

  let(:cache_root) { File.join(@tmpdir, 'cache') }
  let(:repository) { described_class.new(cache_root: cache_root) }
  let(:path) { '/books/a.epub' }
  let(:size) { 123_456 }
  let(:modified) { '2024-01-01T00:00:00Z' }

  def cache_file_for(path, cache_root)
    File.join(
      cache_root,
      'book_metadata',
      'v1',
      "#{Digest::SHA256.hexdigest(path.to_s)}.json"
    )
  end

  it 'returns nil on cache miss' do
    expect(repository.fetch(path: path, size: size, modified: modified)).to be_nil
  end

  it 'round-trips successful display metadata' do
    repository.write_success(
      path: path,
      size: size,
      modified: modified,
      metadata: { title: 'Book', authors: ['Writer'], year: '2024' }
    )

    entry = repository.fetch(path: path, size: size, modified: modified)

    expect(entry).to eq(
      status: :ok,
      metadata: { title: 'Book', authors: ['Writer'], year: '2024' }
    )
  end

  it 'round-trips cached extraction failures' do
    repository.write_error(
      path: path,
      size: size,
      modified: modified,
      error_class: 'Shoko::MalformedMetadataInputError',
      error_message: 'bad metadata'
    )

    entry = repository.fetch(path: path, size: size, modified: modified)

    expect(entry).to eq(
      status: :error,
      error_class: 'Shoko::MalformedMetadataInputError',
      error_message: 'bad metadata'
    )
  end

  it 'treats path mismatches as misses' do
    cache_file = cache_file_for(path, cache_root)
    FileUtils.mkdir_p(File.dirname(cache_file))
    File.write(
      cache_file,
      JSON.generate(
        'version' => described_class::VERSION,
        'path' => '/books/other.epub',
        'size' => size,
        'modified' => modified,
        'status' => 'ok',
        'metadata' => { 'title' => 'Book' }
      )
    )

    expect(repository.fetch(path: path, size: size, modified: modified)).to be_nil
  end

  it 'invalidates entries when size or modified time changes' do
    repository.write_success(path: path, size: size, modified: modified, metadata: { title: 'Book' })

    expect(repository.fetch(path: path, size: size + 1, modified: modified)).to be_nil
    expect(repository.fetch(path: path, size: size, modified: '2024-01-02T00:00:00Z')).to be_nil
  end

  it 'deletes corrupt JSON and treats it as a miss' do
    cache_file = cache_file_for(path, cache_root)
    FileUtils.mkdir_p(File.dirname(cache_file))
    File.write(cache_file, '{')

    expect(repository.fetch(path: path, size: size, modified: modified)).to be_nil
    expect(File.exist?(cache_file)).to be(false)
  end
end
