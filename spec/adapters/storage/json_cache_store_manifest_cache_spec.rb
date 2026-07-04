# frozen_string_literal: true

require 'tmpdir'
require 'json'
require 'spec_helper'

RSpec.describe Shoko::Adapters::Storage::JsonCacheStore do
  let(:rows) do
    [
      {
        'source_sha' => 'a' * 64,
        'source_path' => '/tmp/a.epub',
        'source_mtime' => 100.0,
        'source_size_bytes' => 123,
        'updated_at' => 200.0,
      },
      {
        'source_sha' => 'b' * 64,
        'source_path' => '/tmp/b.epub',
        'source_mtime' => 101.0,
        'source_size_bytes' => 456,
        'updated_at' => 201.0,
      },
    ]
  end

  around do |example|
    described_class.clear_manifest_rows_cache
    example.run
    described_class.clear_manifest_rows_cache
  end

  it 'returns identical manifest rows with cache enabled and disabled' do
    Dir.mktmpdir('json-cache-store-manifest-spec') do |dir|
      File.write(File.join(dir, described_class::MANIFEST_FILENAME), JSON.generate(rows))

      cached = described_class.with_manifest_rows_cache(enabled: true) { described_class.manifest_rows(dir) }
      uncached = described_class.with_manifest_rows_cache(enabled: false) { described_class.manifest_rows(dir) }

      expect(cached).to eq(rows)
      expect(uncached).to eq(rows)
    end
  end

  it 'reads manifest file once when cache is enabled' do
    Dir.mktmpdir('json-cache-store-manifest-spec') do |dir|
      File.write(File.join(dir, described_class::MANIFEST_FILENAME), JSON.generate(rows))

      described_class.with_manifest_rows_cache(enabled: true) do
        expect(described_class).to receive(:read_manifest_file).once.and_call_original

        3.times { described_class.manifest_rows(dir) }
      end
    end
  end

  it 'reads manifest file every time when cache is disabled' do
    Dir.mktmpdir('json-cache-store-manifest-spec') do |dir|
      File.write(File.join(dir, described_class::MANIFEST_FILENAME), JSON.generate(rows))

      described_class.with_manifest_rows_cache(enabled: false) do
        expect(described_class).to receive(:read_manifest_file).exactly(3).times.and_call_original

        3.times { described_class.manifest_rows(dir) }
      end
    end
  end

  it 'never loses rows when two writers update the manifest concurrently' do
    Dir.mktmpdir('json-cache-store-manifest-spec') do |dir|
      # Two independent store instances stand in for the prepagination child
      # process and the parent app: each opens its own lock file descriptor,
      # so the sidecar flock serializes them exactly as it does across
      # processes. Without the lock, interleaved read-modify-write cycles
      # drop rows.
      stores = Array.new(2) { described_class.new(cache_root: dir) }
      rows_per_writer = 12

      threads = stores.each_with_index.map do |store, writer|
        Thread.new do
          rows_per_writer.times do |i|
            sha = format('%02d', writer) + format('%062d', i)
            row = { 'source_sha' => sha, 'source_path' => "/tmp/#{writer}-#{i}.epub" }
            store.send(:update_manifest, row, cache_size_bytes: 1)
          end
        end
      end
      threads.each(&:join)

      described_class.clear_manifest_rows_cache
      shas = described_class.manifest_rows(dir).map { |row| row['source_sha'] }
      expect(shas.length).to eq(2 * rows_per_writer)
      expect(shas.uniq.length).to eq(2 * rows_per_writer)
    end
  end
end
