# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'json'
require 'open3'

RSpec.describe Shoko::Composition::DependencyContainer do
  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  describe Shoko::Composition::ContainerFactory do
    describe '.create_default_container' do
      subject(:container) { described_class.create_default_container }

      it 'creates a valid container' do
        expect(container).to be_a(Shoko::Composition::DependencyContainer)
      end

      describe 'infrastructure services' do
        it 'resolves event_bus' do
          expect(container.resolve(:event_bus)).to be_a(Shoko::Application::State::EventBus)
        end

        it 'resolves global_state' do
          expect(container.resolve(:global_state)).to be_a(Shoko::Application::State::ObserverStateStore)
        end

        it 'resolves domain_event_bus' do
          expect(container.resolve(:domain_event_bus)).to be_a(Shoko::Core::Events::DomainEventBus)
        end

        it 'resolves logger instance' do
          expect(container.resolve(:logger)).to be_a(Shoko::Adapters::Monitoring::LoggerAdapter)
        end

        it 'resolves performance_monitor class' do
          expect(container.resolve(:performance_monitor)).to be_a(Shoko::Adapters::Monitoring::PerformanceMonitor)
        end

        it 'resolves pagination_cache module' do
          expect(container.resolve(:pagination_cache)).to eq(Shoko::Adapters::Storage::PaginationCache)
        end

        it 'resolves cache_paths module' do
          expect(container.resolve(:cache_paths)).to eq(Shoko::Adapters::Storage::CachePaths)
        end

        it 'archives mismatched persisted roots before initializing global state' do
          Dir.mktmpdir do |root|
            config_home = File.join(root, 'config')
            cache_home = File.join(root, 'cache')

            with_env('XDG_CONFIG_HOME' => config_home, 'XDG_CACHE_HOME' => cache_home) do
              config_root = Shoko::Adapters::Storage::ConfigPaths.config_root
              cache_root = Shoko::Adapters::Storage::CachePaths.cache_root
              FileUtils.mkdir_p(config_root)
              FileUtils.mkdir_p(cache_root)
              File.write(File.join(config_root, 'config.json'), JSON.pretty_generate(schema_version: 1, theme: 'default'))
              File.write(File.join(config_root, 'progress.json'), 'legacy-progress')
              File.write(File.join(cache_root, 'cache_manifest.json'), 'legacy-cache')

              runtime_container = described_class.create_default_container
              state = runtime_container.resolve(:global_state)

              config_archives = Dir.glob(File.join(config_home, 'shoko-pre-hex-v2-*'))
              cache_archives = Dir.glob(File.join(cache_home, 'shoko-pre-hex-v2-*'))

              expect(state.get(%i[config schema_version])).to eq(Shoko::Application::Ports::Outbound::State::ConfigSnapshot::SCHEMA_VERSION)
              expect(File).to exist(File.join(config_root, 'config.json'))
              expect(config_archives.length).to eq(1)
              expect(cache_archives.length).to eq(1)
              expect(File.read(File.join(config_archives.first, 'progress.json'))).to eq('legacy-progress')
              expect(File.read(File.join(cache_archives.first, 'cache_manifest.json'))).to eq('legacy-cache')
            end
          end
        end
      end

      describe 'hexagonal adapters' do
        it 'resolves reader_state_reader in a fresh ruby process' do
          code = <<~RUBY
            $LOAD_PATH.unshift File.expand_path('lib', #{File.expand_path('../..', __dir__).dump})
            require 'shoko/composition/container_factory'
            container = Shoko::Composition::ContainerFactory.create_default_container
            puts container.resolve(:reader_state_reader).class.name
          RUBY

          env = {
            'XDG_CONFIG_HOME' => ENV.fetch('XDG_CONFIG_HOME', nil),
            'XDG_CACHE_HOME' => ENV.fetch('XDG_CACHE_HOME', nil),
          }.compact
          stdout, stderr, status = Open3.capture3(env, 'ruby', '-e', code)

          expect(status.success?).to be(true), stderr
          expect(stdout.strip).to eq('Shoko::Adapters::Runtime::SessionState::ReaderSnapshotProjectionAdapter')
        end

        it 'checks dictionary availability in a fresh ruby process without missing constants' do
          code = <<~RUBY
            $LOAD_PATH.unshift File.expand_path('lib', #{File.expand_path('../..', __dir__).dump})
            require 'json'
            require 'shoko/composition/container_factory'
            container = Shoko::Composition::ContainerFactory.create_default_container

            begin
              available = container.resolve(:dictionary_availability).sqlite3_available?
              puts JSON.dump(ok: true, available: available, error_class: nil)
            rescue => e
              puts JSON.dump(ok: false, available: nil, error_class: e.class.name)
            end
          RUBY

          env = {
            'XDG_CONFIG_HOME' => ENV.fetch('XDG_CONFIG_HOME', nil),
            'XDG_CACHE_HOME' => ENV.fetch('XDG_CACHE_HOME', nil),
          }.compact
          stdout, stderr, status = Open3.capture3(env, 'ruby', '-e', code)

          expect(status.success?).to be(true), stderr

          payload = JSON.parse(stdout)
          expect(payload.fetch('error_class')).to satisfy do |error_class|
            [nil, 'Shoko::DependencyUnavailableError'].include?(error_class)
          end
        end

        it 'resolves split registration adapters in a fresh ruby process' do
          code = <<~RUBY
            $LOAD_PATH.unshift File.expand_path('lib', #{File.expand_path('../..', __dir__).dump})
            require 'json'
            require 'shoko/composition/container_factory'
            container = Shoko::Composition::ContainerFactory.create_default_container

            begin
              display = container.resolve(:display_capabilities).class.name
              cache_manager = container.resolve(:cache_manager).class.name
              puts JSON.dump(ok: true, display: display, cache_manager: cache_manager, error_class: nil)
            rescue => e
              puts JSON.dump(ok: false, display: nil, cache_manager: nil, error_class: e.class.name)
            end
          RUBY

          env = {
            'XDG_CONFIG_HOME' => ENV.fetch('XDG_CONFIG_HOME', nil),
            'XDG_CACHE_HOME' => ENV.fetch('XDG_CACHE_HOME', nil),
          }.compact
          stdout, stderr, status = Open3.capture3(env, 'ruby', '-e', code)

          expect(status.success?).to be(true), stderr

          payload = JSON.parse(stdout)
          expect(payload.fetch('error_class')).to be_nil
          expect(payload.fetch('display')).to eq('Shoko::Adapters::Output::Kitty::DisplayCapabilities')
          expect(payload.fetch('cache_manager')).to eq('Shoko::Adapters::Storage::CacheManagerAdapter')
        end

        it 'does not register deleted legacy read-side aliases' do
          expect(container.registered?(:config_reader)).to be(false)
          expect(container.registered?(:reader_navigation_reader)).to be(false)
          expect(container.registered?(:ui_state_reader)).to be(false)
          expect(container.registered?(:sidebar_state_reader)).to be(false)
          expect(container.registered?(:menu_state_reader)).to be(false)
        end

        it 'resolves app_config_store adapter' do
          adapter = container.resolve(:app_config_store)
          expect(adapter).to be_a(Shoko::Adapters::Runtime::SessionState::AppConfigStoreAdapter)
        end

        it 'resolves reader_session_store adapter' do
          adapter = container.resolve(:reader_session_store)
          expect(adapter).to be_a(Shoko::Adapters::Runtime::SessionState::ReaderSessionStoreAdapter)
        end

        it 'resolves reader_session_mutator adapter-local writer' do
          adapter = container.resolve(:reader_session_mutator)
          expect(adapter).to be_a(Shoko::Adapters::Runtime::SessionState::ReaderSessionMutator)
        end

        it 'resolves reader_runtime_context adapter' do
          adapter = container.resolve(:reader_runtime_context)
          expect(adapter).to be_a(Shoko::Adapters::Runtime::SessionState::ReaderRuntimeContextAdapter)
        end

        it 'resolves rendered_content_reader adapter' do
          adapter = container.resolve(:rendered_content_reader)
          expect(adapter).to be_a(Shoko::Adapters::Runtime::SessionState::RenderedContentReaderAdapter)
        end

        it 'app_config_store exposes direct config reads' do
          adapter = container.resolve(:app_config_store)
          expect(adapter).to respond_to(:page_numbering_mode)
          expect(adapter).to respond_to(:view_mode)
          expect(adapter).to respond_to(:line_spacing)
        end

        it 'reader_session_store exposes focused session reads' do
          adapter = container.resolve(:reader_session_store)
          expect(adapter).to respond_to(:current_page)
          expect(adapter).to respond_to(:mode)
          expect(adapter).not_to respond_to(:sidebar_visible?)
        end

        it 'reader_state_reader exposes broad reader reads and live ui fields' do
          adapter = container.resolve(:reader_state_reader)
          expect(adapter).to respond_to(:sidebar_visible?)
          expect(adapter).to respond_to(:popup_menu)
          expect(adapter).to respond_to(:dictionary_lookup_popup)
        end

        it 'builds folder import warmup against the reader view state store' do
          page_calculator = instance_double(
            'PageCalculator',
            reset_session!: nil,
            build_dynamic_map!: { total_pages: 42 }
          )
          config = instance_double('Config', page_numbering_mode: :dynamic)
          app_config_store = instance_double('AppConfigStore', load: config)
          reader_view_state_store = instance_double(
            'ReaderViewStateStore',
            load: Shoko::Application::Ports::Outbound::State::ReaderViewSnapshot.build(sidebar_visible: true)
          )
          reader_runtime_context = instance_double(
            'ReaderRuntimeContext',
            terminal_size: Shoko::Application::Ports::Outbound::State::TerminalSize.build(width: 100, height: 30)
          )
          logger = instance_double('Logger', debug: nil)
          builder_container = double('Container')

          allow(builder_container).to receive(:resolve).with(:page_calculator).and_return(page_calculator)
          allow(builder_container).to receive(:resolve).with(:app_config_store).and_return(app_config_store)
          expect(builder_container).to receive(:resolve).with(:reader_view_state_store).and_return(reader_view_state_store)
          allow(builder_container).to receive(:resolve).with(:reader_runtime_context).and_return(reader_runtime_context)
          allow(builder_container).to receive(:resolve).with(:logger).and_return(logger)

          warmup = Shoko::Composition::ContainerFactory.send(:build_folder_import_document_warmup, builder_container)
          document = instance_double('Document', canonical_path: '/books/a.epub')

          expect(page_calculator).to receive(:build_dynamic_map!).with(
            100,
            30,
            document,
            config_reader: config,
            sidebar_visible: true
          )

          expect(warmup.warm(document)).to eq(:warmed)
        end

        it 'menu_session_store exposes direct menu reads' do
          adapter = container.resolve(:menu_session_store)
          expect(adapter).to respond_to(:selected)
          expect(adapter).to respond_to(:browse_selected)
          expect(adapter).to respond_to(:current_menu_mode)
          expect(adapter).not_to respond_to(:dictionary_entries)
        end

        it 'resolves menu_transient_store adapter' do
          adapter = container.resolve(:menu_transient_store)
          expect(adapter).to be_a(Shoko::Adapters::Runtime::SessionState::MenuTransientStoreAdapter)
        end

        it 'menu_snapshot_projection exposes broad menu reads' do
          adapter = container.resolve(:menu_snapshot_projection)
          expect(adapter).to respond_to(:dictionary_entries)
          expect(adapter).to respond_to(:loading_active?)
          expect(adapter).to respond_to(:current_menu_mode)
        end

        it 'reader_session_store implements load/save snapshot contract' do
          adapter = container.resolve(:reader_session_store)
          expect(adapter).to respond_to(:load)
          expect(adapter).to respond_to(:save)
          expect(adapter).to respond_to(:update)
        end

        it 'reader_session_mutator exposes adapter-local reader/config writes' do
          adapter = container.resolve(:reader_session_mutator)
          expect(adapter).to respond_to(:update_reader)
          expect(adapter).to respond_to(:update_sidebar)
          expect(adapter).to respond_to(:update_config)
          expect(adapter).to respond_to(:clear_selection)
          expect(adapter).to respond_to(:quit_to_menu)
          expect(adapter).to respond_to(:toggle_view_mode)
        end

        it 'menu_session_mutator exposes only direct menu writes' do
          adapter = container.resolve(:menu_session_mutator)
          expect(adapter).to respond_to(:update_menu)
          expect(adapter).not_to respond_to(:update_mode)
        end
      end

      describe 'core ports' do
        it 'resolves text_metrics port' do
          metrics = container.resolve(:text_metrics)
          expect(metrics).to respond_to(:wrap_plain_text)
        end

        it 'resolves display_capabilities port' do
          caps = container.resolve(:display_capabilities)
          expect(caps).to respond_to(:kitty_images_enabled?)
        end

        it 'resolves instrumentation port' do
          instrumentation = container.resolve(:instrumentation)
          expect(instrumentation).to respond_to(:measure)
          expect(instrumentation).to respond_to(:annotate)
        end

        it 'resolves async_executor port' do
          executor = container.resolve(:async_executor)
          expect(executor).to respond_to(:submit)
          expect(executor).to respond_to(:shutdown)
        end

        it 'resolves dictionary_storage port' do
          storage = container.resolve(:dictionary_storage)
          expect(storage).to respond_to(:ensure_databases_path)
          expect(storage).to respond_to(:default_databases_path)
        end

        it 'resolves data_cleanup port' do
          cleanup = container.resolve(:data_cleanup)
          expect(cleanup).to respond_to(:remove_cache_root)
          expect(cleanup).to respond_to(:remove_downloads_root)
        end

        it 'resolves display_metadata_cache port' do
          cache = container.resolve(:display_metadata_cache)
          expect(cache).to be_a(Shoko::Application::Ports::Outbound::DisplayMetadataCache)
        end
      end

      describe 'output services' do
        it 'resolves terminal_service' do
          expect(container.resolve(:terminal_service)).to be_a(Shoko::Adapters::Output::Terminal::TerminalService)
        end

        it 'resolves terminal_session adapter' do
          expect(container.resolve(:terminal_session)).to be_a(Shoko::Adapters::Output::Terminal::TerminalSessionAdapter)
        end

        it 'resolves wrapping_service' do
          expect(container.resolve(:wrapping_service)).to be_a(Shoko::Adapters::Output::Formatting::WrappingService)
        end

        it 'resolves formatting_service' do
          expect(container.resolve(:formatting_service)).to be_a(Shoko::Adapters::Output::Formatting::FormattingService)
        end

        it 'resolves clipboard_service' do
          expect(container.resolve(:clipboard_service)).to be_a(Shoko::Adapters::Output::Clipboard::ClipboardService)
        end

        it 'resolves notification_service' do
          expect(container.resolve(:notification_service)).to be_a(Shoko::Adapters::Output::NotificationService)
        end

        it 'wires notification_service to write reader messages' do
          notification_service = container.resolve(:notification_service)
          state = container.resolve(:global_state)

          notification_service.set_message('Hello toast', 2)

          expect(state.get(%i[reader message])).to eq('Hello toast')
        end

        it 'resolves kitty_image_renderer' do
          expect(container.resolve(:kitty_image_renderer)).to be_a(Shoko::Adapters::Output::Kitty::KittyImageRenderer)
        end

        it 'resolves file_writer' do
          expect(container.resolve(:file_writer)).to be_a(Shoko::Adapters::Storage::FileWriterService)
        end

        it 'resolves instrumentation_service' do
          expect(container.resolve(:instrumentation_service)).to be_a(Shoko::Adapters::Output::InstrumentationService)
        end
      end

      describe 'domain services' do
        it 'resolves domain_event_factory' do
          expect(container.resolve(:domain_event_factory)).to be_a(Shoko::Core::Events::EventFactory)
        end

        it 'resolves page_calculator' do
          expect(container.resolve(:page_calculator)).to be_a(Shoko::Application::Services::Pagination::PageCalculatorService)
        end

        it 'resolves navigation_service' do
          expect(container.resolve(:navigation_service)).to be_a(Shoko::Application::Services::Reader::NavigationService)
        end

        it 'resolves bookmark_service' do
          expect(container.resolve(:bookmark_service)).to be_a(Shoko::Application::Services::Reader::BookmarkService)
        end

        it 'resolves coordinate_service' do
          expect(container.resolve(:coordinate_service)).to be_a(Shoko::Application::Services::CoordinateService)
        end

        it 'resolves popup_position_service' do
          expect(container.resolve(:popup_position_service)).to be_a(Shoko::Application::Services::PopupPositionService)
        end

        it 'resolves selection_service' do
          expect(container.resolve(:selection_service)).to be_a(Shoko::Application::Services::SelectionService)
        end

        it 'resolves layout_service' do
          expect(container.resolve(:layout_service)).to be_a(Shoko::Application::Services::LayoutService)
        end

        it 'resolves annotation_service' do
          expect(container.resolve(:annotation_service)).to be_a(Shoko::Application::Services::Reader::AnnotationStateService)
        end

        it 'resolves core_annotation_service' do
          expect(container.resolve(:core_annotation_service)).to be_a(Shoko::Core::Services::AnnotationService)
        end

        it 'builds dictionary_repository in auto mode when sqlite is available' do
          allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(true)

          expect(container.resolve(:dictionary_repository)).to be_a(Shoko::Adapters::Storage::SqliteDictionaryAdapter)
        end

        it 'builds dictionary_repository in auto mode even when sqlite is unavailable' do
          allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(false)

          expect(container.resolve(:dictionary_repository)).to be_a(Shoko::Adapters::Storage::SqliteDictionaryAdapter)
        end

        it 'does not build dictionary_repository when backend is disabled' do
          allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(true)
          state = container.resolve(:global_state)
          state.update({ %i[config dictionary_backend] => :disabled })

          expect(container.resolve(:dictionary_repository)).to be_nil
        end

        it 'builds dictionary_repository when backend is enabled' do
          allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(true)
          state = container.resolve(:global_state)
          state.update({ %i[config dictionary_backend] => :sqlite })

          repo = container.resolve(:dictionary_repository)
          expect(repo).to be_a(Shoko::Adapters::Storage::SqliteDictionaryAdapter)
        end

        it 'builds dictionary_repository when env enables sqlite' do
          allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(true)
          with_env('SHOKO_DICTIONARY' => 'sqlite') do
            repo = container.resolve(:dictionary_repository)
            expect(repo).to be_a(Shoko::Adapters::Storage::SqliteDictionaryAdapter)
          end
        end
      end

      describe 'application services' do
        it 'resolves catalog_service' do
          expect(container.resolve(:catalog_service)).to be_a(Shoko::Application::UseCases::CatalogService)
        end

        it 'resolves libgen_client' do
          expect(container.resolve(:libgen_client)).to be_a(Shoko::Adapters::BookSources::LibgenClient)
        end

        it 'resolves download_service' do
          expect(container.resolve(:download_service)).to be_a(Shoko::Adapters::BookSources::DownloadService)
        end

        it 'resolves settings_service' do
          expect(container.resolve(:settings_service)).to be_a(Shoko::Application::UseCases::SettingsService)
        end
      end

      describe 'repository services' do
        it 'resolves bookmark_repository' do
          expect(container.resolve(:bookmark_repository)).to be_a(Shoko::Adapters::Storage::Repositories::BookmarkRepository)
        end

        it 'resolves annotation_repository' do
          expect(container.resolve(:annotation_repository)).to be_a(Shoko::Adapters::Storage::Repositories::AnnotationRepository)
        end

        it 'resolves progress_repository' do
          expect(container.resolve(:progress_repository)).to be_a(Shoko::Adapters::Storage::Repositories::ProgressRepository)
        end
      end

      describe 'removed compatibility container keys' do
        it 'fails to resolve removed aliases' do
          %i[
            config_repository
            reader_overlay_reader
            reader_overlay_state_reader
            menu_navigation_reader
            menu_query_reader
            menu_data_reader
            background_worker_factory
            document_service_factory
          ].each do |key|
            expect { container.resolve(key) }.to raise_error(
              Shoko::Composition::DependencyContainer::DependencyError,
              /Service '#{key}' not registered/
            )
          end
        end
      end

      describe 'factory services' do
        it 'resolves epub_cache_factory as callable' do
          factory = container.resolve(:epub_cache_factory)
          expect(factory).to respond_to(:call)
        end

        it 'resolves epub_cache_predicate as callable' do
          predicate = container.resolve(:epub_cache_predicate)
          expect(predicate).to respond_to(:call)
        end

        it 'resolves background_worker_builder as typed port' do
          builder = container.resolve(:background_worker_builder)
          expect(builder).to be_a(Shoko::Application::Ports::Outbound::BackgroundWorkerBuilder)
        end

        it 'resolves xhtml_parser_factory as callable' do
          factory = container.resolve(:xhtml_parser_factory)
          expect(factory).to respond_to(:call)
        end

        it 'resolves document_loader as typed port' do
          loader = container.resolve(:document_loader)
          expect(loader).to be_a(Shoko::Application::Ports::Outbound::DocumentLoader)
        end
      end

      describe 'singleton behavior' do
        it 'returns same instance for singleton services' do
          state1 = container.resolve(:global_state)
          state2 = container.resolve(:global_state)
          expect(state1).to be(state2)
        end

        it 'returns same event_bus instance' do
          bus1 = container.resolve(:event_bus)
          bus2 = container.resolve(:event_bus)
          expect(bus1).to be(bus2)
        end
      end

      describe '.build_format_parser_resolver' do
        it 'uses format-specific parser when chapter metadata keys are strings' do
          fallback_parser = Object.new
          xhtml_factory = ->(_raw) { fallback_parser }
          resolver = described_class.send(:build_format_parser_resolver, xhtml_factory, nil)
          chapter = Struct.new(:metadata).new({ 'format' => 'pdf' })

          parser = resolver.call('{"format":"pdf-layout-v1","lines":[]}', chapter)
          expect(parser).to be_a(Shoko::Adapters::BookSources::Pdf::PdfContentParser)
        end

        it 'falls back to XHTML parser when format is absent' do
          fallback_parser = Object.new
          xhtml_factory = ->(_raw) { fallback_parser }
          resolver = described_class.send(:build_format_parser_resolver, xhtml_factory, nil)
          chapter = Struct.new(:metadata).new({})

          parser = resolver.call('<p>hello</p>', chapter)
          expect(parser).to be(fallback_parser)
        end
      end
    end

    describe '.build_unified_application' do
      it 'builds a unified application with injected dependencies' do
        app = described_class.build_unified_application(epub_path: '/tmp/book.epub', log_config: {})

        expect(app).to be_a(Shoko::Application::UnifiedApplication)
      end
    end
  end
end
