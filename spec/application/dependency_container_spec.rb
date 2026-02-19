# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::DependencyContainer do
  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  describe Shoko::Application::ContainerFactory do
    describe '.create_default_container' do
      subject(:container) { described_class.create_default_container }

      it 'creates a valid container' do
        expect(container).to be_a(Shoko::Application::DependencyContainer)
      end

      describe 'infrastructure services' do
        it 'resolves event_bus' do
          expect(container.resolve(:event_bus)).to be_a(Shoko::Adapters::State::EventBus)
        end

        it 'resolves global_state' do
          expect(container.resolve(:global_state)).to be_a(Shoko::Adapters::State::ObserverStateStore)
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
      end

      describe 'hexagonal adapters' do
        it 'resolves config_reader adapter' do
          adapter = container.resolve(:config_reader)
          expect(adapter).to be_a(Shoko::Adapters::State::ConfigReaderAdapter)
        end

        it 'resolves state_writer adapter' do
          adapter = container.resolve(:state_writer)
          expect(adapter).to be_a(Shoko::Adapters::State::StateWriterAdapter)
        end

        it 'resolves rendered_content_reader adapter' do
          adapter = container.resolve(:rendered_content_reader)
          expect(adapter).to be_a(Shoko::Adapters::State::RenderedContentReaderAdapter)
        end

        it 'config_reader implements ConfigReader port' do
          adapter = container.resolve(:config_reader)
          expect(adapter).to respond_to(:page_numbering_mode)
          expect(adapter).to respond_to(:view_mode)
          expect(adapter).to respond_to(:line_spacing)
        end

        it 'state_writer implements StateWriter port' do
          adapter = container.resolve(:state_writer)
          expect(adapter).to respond_to(:update_pagination_state)
          expect(adapter).to respond_to(:update_page)
          expect(adapter).to respond_to(:update_selections)
          expect(adapter).to respond_to(:update_ui_loading)
          expect(adapter).to respond_to(:update_reader)
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
      end

      describe 'output services' do
        it 'resolves terminal_service' do
          expect(container.resolve(:terminal_service)).to be_a(Shoko::Adapters::Output::Terminal::TerminalService)
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
        it 'resolves page_calculator' do
          expect(container.resolve(:page_calculator)).to be_a(Shoko::Core::Services::PageCalculatorService)
        end

        it 'resolves navigation_service' do
          expect(container.resolve(:navigation_service)).to be_a(Shoko::Application::Services::Reader::NavigationService)
        end

        it 'resolves bookmark_service' do
          expect(container.resolve(:bookmark_service)).to be_a(Shoko::Application::Services::Reader::BookmarkService)
        end

        it 'resolves coordinate_service' do
          expect(container.resolve(:coordinate_service)).to be_a(Shoko::Core::Services::CoordinateService)
        end

        it 'resolves popup_position_service' do
          expect(container.resolve(:popup_position_service)).to be_a(Shoko::Application::Services::PopupPositionService)
        end

        it 'resolves selection_service' do
          expect(container.resolve(:selection_service)).to be_a(Shoko::Core::Services::SelectionService)
        end

        it 'resolves layout_service' do
          expect(container.resolve(:layout_service)).to be_a(Shoko::Core::Services::LayoutService)
        end

        it 'resolves annotation_service' do
          expect(container.resolve(:annotation_service)).to be_a(Shoko::Core::Services::AnnotationService)
        end

        it 'builds dictionary_repository in auto mode when sqlite is available' do
          allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(true)

          expect(container.resolve(:dictionary_repository)).to be_a(Shoko::Adapters::Storage::SqliteDictionaryAdapter)
        end

        it 'does not build dictionary_repository in auto mode when sqlite is unavailable' do
          allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(false)

          expect(container.resolve(:dictionary_repository)).to be_nil
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
            menu_navigation_reader
            menu_query_reader
            menu_data_reader
          ].each do |key|
            expect { container.resolve(key) }.to raise_error(
              Shoko::Application::DependencyContainer::DependencyError,
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

        it 'resolves background_worker_factory as callable' do
          factory = container.resolve(:background_worker_factory)
          expect(factory).to respond_to(:call)
        end

        it 'resolves xhtml_parser_factory as callable' do
          factory = container.resolve(:xhtml_parser_factory)
          expect(factory).to respond_to(:call)
        end

        it 'resolves document_service_factory as callable' do
          factory = container.resolve(:document_service_factory)
          expect(factory).to respond_to(:call)
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
          expect(parser).to be_a(Shoko::Core::BookFormats::Pdf::PdfContentParser)
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
  end
end
