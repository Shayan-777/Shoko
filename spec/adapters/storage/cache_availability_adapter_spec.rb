# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'tmpdir'

require 'spec_helper'

RSpec.describe Shoko::Adapters::Storage::CacheAvailabilityAdapter do
  around do |example|
    Dir.mktmpdir('shoko-cache-spec') do |dir|
      @tmp_dir = dir
      example.run
    end
  end

  def cache_root
    File.join(@tmp_dir, 'cache')
  end

  def write_manifest(rows)
    FileUtils.mkdir_p(cache_root)
    path = File.join(cache_root, 'cache_manifest.json')
    File.write(path, JSON.generate(rows))
  end

  it 'returns true when manifest and payload exist for the source' do
    FileUtils.mkdir_p(cache_root)
    epub_path = File.join(@tmp_dir, 'book.epub')
    File.write(epub_path, 'content')

    sha = Digest::SHA256.file(epub_path).hexdigest
    payload_path = File.join(cache_root, "#{sha}.json")
    File.write(payload_path, '{}')

    row = {
      'source_sha' => sha,
      'source_path' => epub_path,
      'source_mtime' => File.mtime(epub_path).utc.to_f,
      'source_size_bytes' => File.size(epub_path),
      'source_fingerprint' => Shoko::Adapters::Storage::SourceFingerprint.compute(epub_path),
      'updated_at' => Time.now.utc.to_f,
    }
    write_manifest([row])

    adapter = described_class.new(cache_root: cache_root)
    expect(adapter.cache_available?(epub_path)).to be(true)
  end

  it 'returns false when payload is missing' do
    FileUtils.mkdir_p(cache_root)
    epub_path = File.join(@tmp_dir, 'book.epub')
    File.write(epub_path, 'content')

    sha = Digest::SHA256.file(epub_path).hexdigest
    row = {
      'source_sha' => sha,
      'source_path' => epub_path,
      'source_mtime' => File.mtime(epub_path).utc.to_f,
      'source_size_bytes' => File.size(epub_path),
      'source_fingerprint' => Shoko::Adapters::Storage::SourceFingerprint.compute(epub_path),
      'updated_at' => Time.now.utc.to_f,
    }
    write_manifest([row])

    adapter = described_class.new(cache_root: cache_root)
    expect(adapter.cache_available?(epub_path)).to be(false)
  end

  it 'returns true for valid cache pointer files' do
    FileUtils.mkdir_p(cache_root)
    source_path = File.join(@tmp_dir, 'source.epub')
    File.write(source_path, 'content')

    sha = Digest::SHA256.file(source_path).hexdigest
    payload_path = File.join(cache_root, "#{sha}.json")
    File.write(payload_path, '{}')

    pointer_path = File.join(cache_root, "#{sha}.cache")
    manager = Shoko::Adapters::Storage::CachePointerManager.new(pointer_path)
    manager.write(
      'format' => Shoko::Adapters::Storage::CachePointerManager::POINTER_FORMAT,
      'version' => Shoko::Adapters::Storage::CachePointerManager::POINTER_VERSION,
      'sha256' => sha,
      'source_path' => source_path,
      'generated_at' => Time.now.utc.iso8601,
      'engine' => Shoko::Adapters::Storage::JsonCacheStore::ENGINE
    )

    adapter = described_class.new(cache_root: cache_root)
    expect(adapter.cache_available?(pointer_path)).to be(true)
  end
end
