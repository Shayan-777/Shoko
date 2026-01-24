# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Storage::Repositories::ConfigRepository do
  let(:null_logger) { Shoko::Core::Services::NullLogger.new }
  let(:terminal_capabilities) { Shoko::Core::Services::DefaultTerminalCapabilities.new }
  let(:config_dir) { @tmpdir }
  let(:config_file) { File.join(@tmpdir, 'config.json') }
  let(:config_storage) do
    storage = Object.new
    dir = config_dir
    file = config_file
    storage.define_singleton_method(:config_dir) { dir }
    storage.define_singleton_method(:config_file) { file }
    storage.define_singleton_method(:ensure_config_dir) { FileUtils.mkdir_p(dir) }
    storage.define_singleton_method(:atomic_write) do |path, data|
      File.write(path, data)
    end
    storage.define_singleton_method(:read_file) do |path|
      File.exist?(path) ? File.read(path) : nil
    end
    storage
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      example.run
    end
  end

  let(:state_store) do
    bus = Shoko::Application::Infrastructure::EventBus.new(logger: null_logger)
    Shoko::Application::Infrastructure::StateStore.new(
      bus,
      config_storage: config_storage,
      terminal_capabilities: terminal_capabilities
    )
  end
  subject(:repo) { described_class.new(global_state: state_store) }

  it 'includes dictionary defaults in all_config' do
    config = repo.all_config

    expect(config).to include(
      dictionary_source_lang: 'auto',
      dictionary_target_lang: 'en',
      dictionary_path: nil,
      dictionary_backend: nil
    )
  end
end
