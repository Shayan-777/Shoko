# frozen_string_literal: true

module Shoko
  module Application
    module Composition
      module ContainerFactory
        # Registers ports, adapters, and repositories in the DI container.
        module PortAndRepositoryRegistration
          # Register core port adapters.
          def register_core_ports(container)
            container.register(:text_metrics, Shoko::Adapters::Output::Terminal::TextMetrics)
            container.register_singleton(:display_capabilities) do |_c|
              Shoko::Adapters::Output::Kitty::DisplayCapabilities.new
            end
            container.register_singleton(:instrumentation) { |c| c.resolve(:instrumentation_service) }
            container.register_factory(:async_executor) do |c|
              executor = (c.resolve(:background_worker) if c.registered?(:background_worker))
              executor || Shoko::Core::Services::InlineExecutor.new
            rescue StandardError
              Shoko::Core::Services::InlineExecutor.new
            end

            # New hexagonal ports
            container.register_singleton(:config_storage) do |_c|
              Shoko::Adapters::Storage::ConfigStorageAdapter.new
            end
            container.register_singleton(:book_finder) do |c|
              config_storage = c.resolve(:config_storage)
              finder = Shoko::Adapters::BookSources::BookFinder.new(
                config_root: config_storage.config_dir,
                cache_writer: Shoko::Adapters::Storage::AtomicFileWriter,
                logger: c.resolve_optional(:logger)
              )
              # Keep class-level shims functional for one compatibility cycle.
              Shoko::Adapters::BookSources::BookFinder.install_default(finder)
              finder
            end

            container.register_singleton(:terminal_capabilities) do |_c|
              Shoko::Adapters::Output::TerminalCapabilitiesAdapter.new
            end
            container.register_singleton(:layout_metrics) do |_c|
              Shoko::Adapters::State::LayoutMetricsAdapter.new
            end
            container.register_singleton(:key_classifier) do |_c|
              Shoko::Adapters::Input::KeyClassifierAdapter.new(
                command_factory: Shoko::Adapters::Input::CommandFactory
              )
            end
            container.register_singleton(:text_sanitizer) do |_c|
              Shoko::Adapters::Output::Terminal::TextSanitizerAdapter.new
            end
            container.register_singleton(:dictionary_availability) do |_c|
              Shoko::Adapters::Storage::DictionaryAvailabilityAdapter.new(
                backend_class: Shoko::Adapters::Storage::SqliteDictionaryAdapter
              )
            end
            container.register_singleton(:dictionary_storage) do |_c|
              Shoko::Adapters::Storage::DictionaryStorageAdapter.new
            end
            container.register_singleton(:data_cleanup) do |_c|
              Shoko::Adapters::Storage::DataCleanupAdapter.new
            end
            container.register_singleton(:cache_manager) do |c|
              Shoko::Adapters::Storage::CacheManagerAdapter.new(
                epub_cache_clearer: -> { c.resolve(:book_finder).clear_cache },
                cache_path_provider: Shoko::Adapters::Storage::CachePaths
              )
            end
            container.register_singleton(:metadata_reader) do |_c|
              Shoko::Adapters::BookSources::MetadataReaderAdapter.new
            end
            container.register_singleton(:file_probe) do |_c|
              Shoko::Adapters::Storage::FileProbeAdapter.new
            end
            container.register_singleton(:path_ops) do |_c|
              Shoko::Adapters::Storage::PathOpsAdapter.new
            end
            container.register_singleton(:input_system_factory) do |_c|
              Shoko::Adapters::Input::InputSystemFactoryAdapter.new
            end
            container.register_singleton(:rendering_factory) do |_c|
              Shoko::Adapters::Output::Ui::RenderingFactoryAdapter.new
            end
          end

          # Register repository implementations
          def register_repositories(container)
            container.register_factory(:bookmark_repository) do |c|
              Shoko::Adapters::Storage::Repositories::BookmarkRepository.new(
                file_writer: c.resolve(:file_writer),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:annotation_repository) do |c|
              Shoko::Adapters::Storage::Repositories::AnnotationRepository.new(
                file_writer: c.resolve(:file_writer),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:progress_repository) do |c|
              Shoko::Adapters::Storage::Repositories::ProgressRepository.new(
                file_writer: c.resolve(:file_writer),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:config_repository) do |c|
              Shoko::Adapters::Storage::Repositories::ConfigRepository.new(
                global_state: c.resolve(:global_state),
                logger: c.resolve_optional(:logger)
              )
            end
          end

          # Register state management services
          def register_state_management(container, event_bus)
            container.register_singleton(:global_state) do |c|
              Shoko::Adapters::State::ObserverStateStore.new(
                event_bus,
                config_storage: c.resolve(:config_storage),
                terminal_capabilities: c.resolve(:terminal_capabilities),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:state_store) { |c| c.resolve(:global_state) }
            register_hexagonal_adapters(container)
          end

          # Register hexagonal architecture port adapters
          def register_hexagonal_adapters(container)
            container.register_factory(:config_reader) do |c|
              Shoko::Adapters::State::ConfigReaderAdapter.new(c.resolve(:global_state))
            end
            container.register_factory(:state_writer) do |c|
              Shoko::Adapters::State::StateWriterAdapter.new(c.resolve(:global_state))
            end
            container.register_factory(:rendered_content_reader) do |c|
              Shoko::Adapters::State::RenderedContentReaderAdapter.new(
                c.resolve(:global_state),
                render_registry: c.resolve(:render_registry)
              )
            end
            container.register_factory(:reader_state_reader) do |c|
              Shoko::Adapters::State::ReaderStateReaderAdapter.new(c.resolve(:global_state))
            end
            container.register_factory(:reader_navigation_reader) { |c| c.resolve(:reader_state_reader) }
            container.register_factory(:reader_overlay_reader) { |c| c.resolve(:reader_state_reader) }
            container.register_factory(:reader_overlay_state_reader) { |c| c.resolve(:reader_state_reader) }
            container.register_factory(:dictionary_ui_session) do |c|
              Shoko::Adapters::Output::Ui::Sessions::DictionaryUiSessionAdapter.new(
                reader_state_reader: c.resolve(:reader_state_reader),
                state_writer: c.resolve(:reader_state_writer),
                ui_component_factory: c.resolve(:ui_component_factory),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:in_book_search_ui_session) do |c|
              Shoko::Adapters::Output::Ui::Sessions::InBookSearchUiSessionAdapter.new(
                reader_state_reader: c.resolve(:reader_state_reader),
                state_writer: c.resolve(:reader_state_writer),
                ui_component_factory: c.resolve(:ui_component_factory),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:annotation_overlay_ui_session) do |c|
              Shoko::Adapters::Output::Ui::Sessions::AnnotationOverlayUiSessionAdapter.new(
                reader_state_reader: c.resolve(:reader_state_reader),
                state_writer: c.resolve(:reader_state_writer),
                ui_component_factory: c.resolve(:ui_component_factory),
                logger: c.resolve_optional(:logger)
              )
            end
            container.register_factory(:ui_state_reader) do |c|
              Shoko::Adapters::State::UIStateReaderAdapter.new(c.resolve(:global_state))
            end
            container.register_factory(:observer_registry) do |c|
              Shoko::Adapters::State::ObserverRegistryAdapter.new(c.resolve(:global_state))
            end
            container.register_factory(:render_state_writer) do |c|
              Shoko::Adapters::State::RenderStateWriterAdapter.new(
                c.resolve(:global_state),
                render_registry: c.resolve(:render_registry),
                logger: c.resolve(:logger)
              )
            end
            container.register_factory(:progress_state_reader) do |c|
              Shoko::Adapters::State::ProgressStateReaderAdapter.new(c.resolve(:global_state))
            end
            container.register_factory(:sidebar_state_reader) do |c|
              Shoko::Adapters::State::SidebarStateReaderAdapter.new(c.resolve(:global_state))
            end
            container.register_factory(:menu_state_reader) do |c|
              Shoko::Adapters::State::MenuStateReaderAdapter.new(c.resolve(:global_state))
            end
            container.register_factory(:menu_navigation_reader) { |c| c.resolve(:menu_state_reader) }
            container.register_factory(:menu_query_reader) { |c| c.resolve(:menu_state_reader) }
            container.register_factory(:menu_data_reader) { |c| c.resolve(:menu_state_reader) }
            container.register_factory(:menu_state_writer) do |c|
              Shoko::Adapters::State::MenuStateWriterAdapter.new(c.resolve(:global_state))
            end
            container.register_factory(:pagination_state_writer) { |c| c.resolve(:state_writer) }
            container.register_factory(:reader_state_writer) { |c| c.resolve(:state_writer) }
            container.register_factory(:notification_writer) do |c|
              Shoko::Adapters::State::NotificationWriterAdapter.new(
                c.resolve(:global_state),
                text_sanitizer: c.resolve_optional(:text_sanitizer)
              )
            end
            container.register_singleton(:command_port) do |_c|
              Shoko::Adapters::State::CommandPortAdapter.new
            end
            container.register_factory(:view_model_builder_factory) do |c|
              reader_state_reader = c.resolve(:reader_state_reader)
              config_reader = c.resolve(:config_reader)
              lambda { |doc|
                Shoko::Application::UI::ReaderViewModelBuilder.new(
                  reader_state_reader: reader_state_reader,
                  config_reader: config_reader,
                  doc: doc
                )
              }
            end
          end

          # Register library scanning services
          def register_library_services(container)
            container.register_singleton(:cached_library_repository) do |_c|
              Shoko::Adapters::Storage::Repositories::CachedLibraryRepository.new
            end
            container.register_factory(:library_scanner) do |c|
              Shoko::Adapters::BookSources::LibraryScanner.new(
                logger: c.resolve(:logger),
                book_finder: c.resolve(:book_finder)
              )
            end
          end
        end
      end
    end
  end
end
