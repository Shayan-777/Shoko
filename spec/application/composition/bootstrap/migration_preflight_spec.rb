# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Shoko::Application::Composition::Bootstrap::MigrationPreflight do
  around do |example|
    Dir.mktmpdir do |tmp|
      config_home = File.join(tmp, 'config_home')
      cache_home = File.join(tmp, 'cache_home')
      with_env('XDG_CONFIG_HOME' => config_home, 'XDG_CACHE_HOME' => cache_home) { example.run }
    end
  end

  let(:config_root) { Shoko::Adapters::Storage::ConfigPaths.config_root }
  let(:cache_root) { Shoko::Adapters::Storage::CachePaths.cache_root }

  def write_legacy_file(name, payload)
    FileUtils.mkdir_p(config_root)
    File.write(File.join(config_root, name), payload)
  end

  it 'does not require migration for a clean install' do
    expect(described_class.migration_required?).to be(false)
  end

  it 'requires migration when legacy config data exists without marker' do
    write_legacy_file('config.json', '{}')

    expect(described_class.migration_required?).to be(true)
  end

  it 'does not require migration when marker is present' do
    write_legacy_file('config.json', '{}')
    File.write(described_class.marker_path, '{"version":2}')

    expect(described_class.migration_required?).to be(false)
  end

  it 'raises actionable error when migration is required' do
    write_legacy_file('bookmarks.json', '[]')

    expect { described_class.ensure_migrated! }
      .to raise_error(described_class::MigrationRequiredError, /bin\/migrate-v2/)
  end

  it 'considers cache artifacts as legacy signatures' do
    FileUtils.mkdir_p(cache_root)
    File.write(File.join(cache_root, 'legacy.cache'), 'x')

    expect(described_class.migration_required?).to be(true)
  end
end
