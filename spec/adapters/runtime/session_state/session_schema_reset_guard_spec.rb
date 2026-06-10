# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'

RSpec.describe Shoko::Adapters::Runtime::SessionState::SessionSchemaResetGuard do
  around do |example|
    Dir.mktmpdir do |dir|
      config_home = File.join(dir, 'config')
      cache_home = File.join(dir, 'cache')
      with_env('XDG_CONFIG_HOME' => config_home, 'XDG_CACHE_HOME' => cache_home) { example.run }
    end
  end

  let(:config_storage) { Shoko::Adapters::Storage::ConfigStorageAdapter.new }
  let(:cache_paths) { Shoko::Adapters::Storage::CachePaths }
  let(:logger) { instance_double('Logger', info: nil) }

  def config_root = Shoko::Adapters::Storage::ConfigPaths.config_root

  def cache_root = cache_paths.cache_root

  def seed_user_data(config_root)
    File.write(File.join(config_root, 'annotations.json'), 'user-annotations')
    File.write(File.join(config_root, 'bookmarks.json'), 'user-bookmarks')
    File.write(File.join(config_root, 'progress.json'), 'user-progress')
    FileUtils.mkdir_p(File.join(config_root, 'downloads'))
    File.write(File.join(config_root, 'downloads', 'book.epub'), 'downloaded-book')
  end

  def expect_user_data_untouched(config_root)
    expect(File.read(File.join(config_root, 'annotations.json'))).to eq('user-annotations')
    expect(File.read(File.join(config_root, 'bookmarks.json'))).to eq('user-bookmarks')
    expect(File.read(File.join(config_root, 'progress.json'))).to eq('user-progress')
    expect(File.read(File.join(config_root, 'downloads', 'book.epub'))).to eq('downloaded-book')
  end

  def run_guard
    described_class.new(
      config_storage: config_storage,
      cache_paths: cache_paths,
      logger: logger
    ).ensure_current_schema!
  end

  it 'archives only config.json and the cache root on schema mismatch, preserving user data' do
    FileUtils.mkdir_p(config_root)
    FileUtils.mkdir_p(cache_root)
    File.write(File.join(config_root, 'config.json'), JSON.pretty_generate(schema_version: 1, view_mode: 'single'))
    seed_user_data(config_root)
    File.write(File.join(cache_root, 'cache_manifest.json'), 'legacy-cache')

    result = run_guard

    config_archives = Dir.glob(File.join(config_root, 'config-pre-v2-*.json'))
    cache_archives = Dir.glob(File.join(File.dirname(cache_root), 'shoko-pre-hex-v2-*'))

    expect(config_archives.length).to eq(1)
    expect(result[:from_schema_version]).to eq(1)
    expect(result[:config_archive]).to eq(config_archives.first)
    expect(result[:cache_archive]).to eq(cache_archives.first)

    expect(File.exist?(File.join(config_root, 'config.json'))).to be(false)
    expect(JSON.parse(File.read(config_archives.first))).to include('schema_version' => 1)
    expect_user_data_untouched(config_root)

    expect(File.exist?(cache_root)).to be(false)
    expect(File.read(File.join(cache_archives.first, 'cache_manifest.json'))).to eq('legacy-cache')

    expect(logger).to have_received(:info).with(
      'session.schema_reset',
      hash_including(
        from_schema_version: 1,
        to_schema_version: 2,
        config_archive: config_archives.first,
        cache_archive: cache_archives.first
      )
    )
  end

  it 'does nothing when the persisted schema version matches' do
    FileUtils.mkdir_p(config_root)
    FileUtils.mkdir_p(cache_root)
    File.write(
      File.join(config_root, 'config.json'),
      JSON.pretty_generate(schema_version: Shoko::Application::Ports::Outbound::State::ConfigSnapshot::SCHEMA_VERSION)
    )
    seed_user_data(config_root)

    result = run_guard

    expect(result).to eq(:pass)
    expect(Dir.glob(File.join(config_root, 'config-pre-v*'))).to be_empty
    expect(Dir.glob(File.join(File.dirname(cache_root), 'shoko-pre-hex-v2-*'))).to be_empty
    expect_user_data_untouched(config_root)
    expect(logger).not_to have_received(:info)
  end

  it 'archives a malformed config.json (from_schema_version nil) and preserves user data' do
    FileUtils.mkdir_p(config_root)
    FileUtils.mkdir_p(cache_root)
    File.write(File.join(config_root, 'config.json'), '{not valid json')
    seed_user_data(config_root)
    File.write(File.join(cache_root, 'cache_manifest.json'), 'legacy-cache')

    result = run_guard

    config_archives = Dir.glob(File.join(config_root, 'config-pre-v2-*.json'))
    cache_archives = Dir.glob(File.join(File.dirname(cache_root), 'shoko-pre-hex-v2-*'))

    expect(config_archives.length).to eq(1)
    expect(result[:from_schema_version]).to be_nil
    expect(result[:config_archive]).to eq(config_archives.first)
    expect(File.read(config_archives.first)).to eq('{not valid json')
    expect_user_data_untouched(config_root)
    expect(File.read(File.join(cache_archives.first, 'cache_manifest.json'))).to eq('legacy-cache')

    expect(logger).to have_received(:info).with(
      'session.schema_reset',
      hash_including(from_schema_version: nil, to_schema_version: 2)
    )
  end

  it 'picks a unique archive name when one already exists for the same timestamp' do
    FileUtils.mkdir_p(config_root)
    File.write(File.join(config_root, 'config.json'), '{not valid json')
    timestamp = Time.now.utc.strftime('%Y%m%d%H%M%S')
    File.write(File.join(config_root, "config-pre-v2-#{timestamp}.json"), 'existing-archive')

    result = run_guard

    expect(result[:config_archive]).not_to be_nil
    expect(File.read(File.join(config_root, "config-pre-v2-#{timestamp}.json"))).to eq('existing-archive')
    expect(result[:config_archive]).to match(/config-pre-v2-\d{14}(-\d+)?\.json\z/)
    expect(File.exist?(result[:config_archive])).to be(true)
  end
end
