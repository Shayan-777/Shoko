# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::SettingsService do
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
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
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
  let(:cache_manager) { double('CacheManager', clear_epub_cache: nil, cache_root: '/tmp/cache') }
  let(:dictionary_availability) { double('DictionaryAvailability', sqlite3_available?: false, databases_present?: false) }

  subject(:service) do
    described_class.new(
      state_store: state_store,
      terminal_service: instance_double('TerminalService'),
      cache_manager: cache_manager,
      dictionary_availability: dictionary_availability
    )
  end

  describe '#toggle_dictionary_backend' do
    it 'toggles dictionary backend between :sqlite and :disabled' do
      expect(state_store.get(%i[config dictionary_backend])).to be_nil

      service.toggle_dictionary_backend
      expect(state_store.get(%i[config dictionary_backend])).to eq(:sqlite)

      service.toggle_dictionary_backend
      expect(state_store.get(%i[config dictionary_backend])).to eq(:disabled)
    end
  end
end
