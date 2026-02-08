# frozen_string_literal: true

require 'json'
require 'tmpdir'
require 'time'
require 'spec_helper'

RSpec.describe Shoko::Adapters::Storage::CachePointerResolver do
  let(:resolver) { described_class.new }
  let(:sha) { 'a' * 64 }

  def write_pointer(path, source_path:)
    payload = {
      'format' => Shoko::Adapters::Storage::CachePointerManager::POINTER_FORMAT,
      'version' => Shoko::Adapters::Storage::CachePointerManager::POINTER_VERSION,
      'sha256' => sha,
      'source_path' => source_path,
      'generated_at' => Time.now.utc.iso8601,
      'engine' => Shoko::Adapters::Storage::JsonCacheStore::ENGINE,
    }
    File.write(path, JSON.generate(payload))
  end

  it 'returns source path fallback from pointer metadata when cache payload is missing' do
    Dir.mktmpdir('pointer-resolver-spec') do |dir|
      pointer_path = File.join(dir, "#{sha}.cache")
      source_path = File.join(dir, 'book.epub')
      File.write(source_path, '')
      write_pointer(pointer_path, source_path: source_path)

      payload = resolver.read_cache(pointer_path, strict: false)

      expect(payload).not_to be_nil
      expect(payload.source_path).to eq(source_path)
    end
  end

  it 'does not use pointer metadata fallback in strict mode' do
    Dir.mktmpdir('pointer-resolver-spec') do |dir|
      pointer_path = File.join(dir, "#{sha}.cache")
      source_path = File.join(dir, 'book.epub')
      File.write(source_path, '')
      write_pointer(pointer_path, source_path: source_path)

      payload = resolver.read_cache(pointer_path, strict: true)

      expect(payload).to be_nil
    end
  end
end
