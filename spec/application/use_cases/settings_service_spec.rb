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
    bus = Shoko::Adapters::Runtime::SessionState::EventBus.new(logger: null_logger)
    Shoko::Adapters::Runtime::SessionState::StateStore.new(
      bus,
      config_storage: config_storage,
      terminal_capabilities: terminal_capabilities
    )
  end
  let(:cache_manager) { double('CacheManager', clear_epub_cache: nil, cache_root: cache_root) }
  let(:dictionary_availability) do
    double('DictionaryAvailability',
           sqlite3_available?: false)
  end
  let(:dictionary_storage) { Shoko::Adapters::Storage::DictionaryStorageAdapter.new }
  let(:data_cleanup) { Shoko::Adapters::Storage::DataCleanupAdapter.new }
  let(:cache_root) { File.join(@tmpdir, 'cache', 'shoko') }
  let(:downloads_root) { File.join(config_storage.config_dir, 'downloads') }
  let(:dictionary_root) { File.join(@tmpdir, 'dictionaries') }
  let(:config_root) { config_storage.config_dir }
  let(:annotations_path) { File.join(config_root, 'annotations.json') }
  let(:bookmarks_path) { File.join(config_root, 'bookmarks.json') }
  let(:progress_path) { File.join(config_root, 'progress.json') }
  let(:config_json_path) { File.join(config_root, 'config.json') }
  let(:recent_repository) { double('RecentFilesRepository', clear: nil) }
  let(:wrapping_service) { double('WrappingService', clear_cache: nil) }

  let(:config_reader) { Shoko::Adapters::Runtime::SessionState::ConfigReaderAdapter.new(state_store) }
  let(:state_writer) { Shoko::Adapters::Runtime::SessionState::StateWriterAdapter.new(state_store) }

  subject(:service) do
    described_class.new(
      config_reader: config_reader,
      state_writer: state_writer,
      cache_manager: cache_manager,
      dictionary_availability: dictionary_availability,
      dictionary_storage: dictionary_storage,
      data_cleanup: data_cleanup,
      recent_files_repository: recent_repository,
      wrapping_service: wrapping_service,
      config_storage: config_storage
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

  describe 'theme settings' do
    it 'cycles through canonical themes' do
      expect(state_store.get(%i[config theme])).to eq(:default)

      next_theme = service.cycle_theme

      expect(next_theme).to eq(:gray)
      expect(state_store.get(%i[config theme])).to eq(:gray)
    end

    it 'sets an explicit canonical theme' do
      result = service.set_theme('sepia')
      expect(result).to eq(:sepia)
      expect(state_store.get(%i[config theme])).to eq(:sepia)
    end

    it 'rejects unsupported themes' do
      expect { service.set_theme('nonexistent') }.to raise_error(ArgumentError, /Unsupported theme/)
    end
  end

  describe '#wipe_cache' do
    before do
      FileUtils.mkdir_p(cache_root)
      FileUtils.mkdir_p(downloads_root)
      FileUtils.mkdir_p(dictionary_root)
      FileUtils.mkdir_p(config_root)
      File.write(File.join(cache_root, 'cache.dat'), 'cache')
      File.write(File.join(downloads_root, 'book.epub'), 'book')
      File.write(File.join(dictionary_root, 'dict.sqlite3'), 'dict')
      File.write(annotations_path, 'annotations')
      File.write(bookmarks_path, 'bookmarks')
      File.write(progress_path, 'progress')
      File.write(config_json_path, 'config')
      state_store.dispatch(Shoko::Adapters::Runtime::SessionState::Actions::UpdateConfigAction.new(dictionary_path: dictionary_root))
    end

    it 'removes cached data when cached option selected' do
      expect(cache_manager).to receive(:clear_epub_cache)
      expect(recent_repository).to receive(:clear)
      expect(wrapping_service).to receive(:clear_cache)
      expect(data_cleanup).to receive(:remove_cache_root).with(cache_root).and_call_original

      service.wipe_cache(cached: true, downloads: false, nuke: false)

      expect(File.directory?(cache_root)).to be(false)
      expect(File.directory?(downloads_root)).to be(true)
      expect(File.directory?(dictionary_root)).to be(true)
    end

    it 'removes downloaded books when downloads option selected' do
      expect(cache_manager).not_to receive(:clear_epub_cache)
      expect(recent_repository).not_to receive(:clear)
      expect(wrapping_service).not_to receive(:clear_cache)
      expect(data_cleanup).to receive(:remove_downloads_root).with(config_root).and_call_original

      service.wipe_cache(cached: false, downloads: true, nuke: false)

      expect(File.directory?(downloads_root)).to be(false)
      expect(File.directory?(cache_root)).to be(true)
      expect(File.directory?(dictionary_root)).to be(true)
      expect(File.exist?(annotations_path)).to be(true)
      expect(File.exist?(bookmarks_path)).to be(true)
      expect(File.exist?(progress_path)).to be(true)
      expect(File.exist?(config_json_path)).to be(true)
    end

    it 'removes selected user data files when options are enabled' do
      expect(data_cleanup).to receive(:remove_user_data_files)
        .with(config_root: config_root, annotations: true, bookmarks: true, progress: true, config_file: true)
        .and_call_original

      service.wipe_cache(cached: false, downloads: false,
                         annotations: true, bookmarks: true,
                         progress: true, config_file: true)

      expect(File.exist?(annotations_path)).to be(false)
      expect(File.exist?(bookmarks_path)).to be(false)
      expect(File.exist?(progress_path)).to be(false)
      expect(File.exist?(config_json_path)).to be(false)
      expect(File.directory?(cache_root)).to be(true)
      expect(File.directory?(downloads_root)).to be(true)
    end

    it 'nukes caches, downloads, and dictionaries when nuke option selected' do
      expect(cache_manager).to receive(:clear_epub_cache)
      expect(recent_repository).to receive(:clear)
      expect(wrapping_service).to receive(:clear_cache)
      expect(dictionary_storage).to receive(:remove_databases_path).with(dictionary_root).and_call_original

      service.wipe_cache(nuke: true)

      expect(File.directory?(cache_root)).to be(false)
      expect(File.directory?(downloads_root)).to be(false)
      expect(File.directory?(dictionary_root)).to be(false)
      expect(File.exist?(annotations_path)).to be(false)
      expect(File.exist?(bookmarks_path)).to be(false)
      expect(File.exist?(progress_path)).to be(false)
      expect(File.exist?(config_json_path)).to be(false)
    end
  end
end
