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

  it 'archives config and cache roots when the persisted schema version mismatches' do
    config_root = Shoko::Adapters::Storage::ConfigPaths.config_root
    cache_root = cache_paths.cache_root
    FileUtils.mkdir_p(config_root)
    FileUtils.mkdir_p(cache_root)
    File.write(File.join(config_root, 'config.json'), JSON.pretty_generate(schema_version: 1, view_mode: 'single'))
    File.write(File.join(config_root, 'progress.json'), 'legacy-progress')
    File.write(File.join(cache_root, 'cache_manifest.json'), 'legacy-cache')

    result = described_class.new(
      config_storage: config_storage,
      cache_paths: cache_paths,
      logger: logger
    ).ensure_current_schema!

    config_archives = Dir.glob(File.join(File.dirname(config_root), 'shoko-pre-hex-v2-*'))
    cache_archives = Dir.glob(File.join(File.dirname(cache_root), 'shoko-pre-hex-v2-*'))

    expect(result[:config_archive]).to eq(config_archives.first)
    expect(result[:cache_archive]).to eq(cache_archives.first)
    expect(File.read(File.join(config_archives.first, 'progress.json'))).to eq('legacy-progress')
    expect(File.read(File.join(cache_archives.first, 'cache_manifest.json'))).to eq('legacy-cache')
    expect(File.exist?(config_root)).to be(false)
    expect(File.exist?(cache_root)).to be(false)
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
    config_root = Shoko::Adapters::Storage::ConfigPaths.config_root
    cache_root = cache_paths.cache_root
    FileUtils.mkdir_p(config_root)
    FileUtils.mkdir_p(cache_root)
    File.write(
      File.join(config_root, 'config.json'),
      JSON.pretty_generate(schema_version: Shoko::Application::Ports::Outbound::State::ConfigSnapshot::SCHEMA_VERSION)
    )

    result = described_class.new(
      config_storage: config_storage,
      cache_paths: cache_paths,
      logger: logger
    ).ensure_current_schema!

    expect(result).to eq(:pass)
    expect(Dir.glob(File.join(File.dirname(config_root), 'shoko-pre-hex-v2-*'))).to be_empty
    expect(Dir.glob(File.join(File.dirname(cache_root), 'shoko-pre-hex-v2-*'))).to be_empty
    expect(logger).not_to have_received(:info)
  end

  it 'archives malformed persisted config instead of silently skipping reset' do
    config_root = Shoko::Adapters::Storage::ConfigPaths.config_root
    cache_root = cache_paths.cache_root
    FileUtils.mkdir_p(config_root)
    FileUtils.mkdir_p(cache_root)
    File.write(File.join(config_root, 'config.json'), '{not valid json')
    File.write(File.join(cache_root, 'cache_manifest.json'), 'legacy-cache')

    result = described_class.new(
      config_storage: config_storage,
      cache_paths: cache_paths,
      logger: logger
    ).ensure_current_schema!

    config_archives = Dir.glob(File.join(File.dirname(config_root), 'shoko-pre-hex-v2-*'))
    cache_archives = Dir.glob(File.join(File.dirname(cache_root), 'shoko-pre-hex-v2-*'))

    expect(result[:config_archive]).to eq(config_archives.first)
    expect(result[:cache_archive]).to eq(cache_archives.first)
    expect(File.read(File.join(cache_archives.first, 'cache_manifest.json'))).to eq('legacy-cache')
    expect(logger).to have_received(:info).with(
      'session.schema_reset',
      hash_including(
        from_schema_version: nil,
        to_schema_version: 2,
        config_archive: config_archives.first,
        cache_archive: cache_archives.first
      )
    )
  end
end
