# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'

RSpec.describe 'bin/migrate-v2 and rollback' do
  def run_script(script_name, env)
    script = File.expand_path("../../bin/#{script_name}", __dir__)
    Open3.capture3(env, RbConfig.ruby, script)
  end

  around do |example|
    Dir.mktmpdir do |tmp|
      @config_home = File.join(tmp, 'config_home')
      @cache_home = File.join(tmp, 'cache_home')
      @env = {
        'XDG_CONFIG_HOME' => @config_home,
        'XDG_CACHE_HOME' => @cache_home
      }
      example.run
    end
  end

  let(:config_root) { File.join(@config_home, 'shoko') }
  let(:cache_root) { File.join(@cache_home, 'shoko') }

  def seed_legacy_state(theme: 'dark')
    FileUtils.mkdir_p(config_root)
    File.write(File.join(config_root, 'config.json'), JSON.dump({ theme: theme }))
    File.write(File.join(config_root, 'annotations.json'), JSON.dump([]))
    File.write(File.join(config_root, 'bookmarks.json'), JSON.dump([]))
    File.write(File.join(config_root, 'progress.json'), JSON.dump({}))
    File.write(File.join(config_root, 'recent.json'), JSON.dump([]))

    FileUtils.mkdir_p(cache_root)
    File.write(File.join(cache_root, 'old-cache.bin'), 'legacy')
  end

  it 'migrates once, creates marker, purges cache, and is idempotent' do
    seed_legacy_state

    _out, err, status = run_script('migrate-v2', @env)
    expect(status.success?).to be(true), err

    marker = File.join(config_root, '.migrated_v2')
    expect(File).to exist(marker)
    expect(Dir).not_to exist(cache_root)

    normalized = JSON.parse(File.read(File.join(config_root, 'config.json')))
    expect(normalized['theme']).to eq('dark')

    out2, err2, status2 = run_script('migrate-v2', @env)
    expect(status2.success?).to be(true), err2
    expect(out2).to include('Already migrated')
  end

  it 'restores latest backup via rollback script' do
    seed_legacy_state(theme: 'dark')

    _out, err, status = run_script('migrate-v2', @env)
    expect(status.success?).to be(true), err

    File.write(File.join(config_root, 'config.json'), JSON.dump({ theme: 'light' }))

    _out2, err2, status2 = run_script('migrate-v2-rollback', @env)
    expect(status2.success?).to be(true), err2

    restored = JSON.parse(File.read(File.join(config_root, 'config.json')))
    expect(restored['theme']).to eq('dark')
    expect(File).not_to exist(File.join(config_root, '.migrated_v2'))
  end
end
