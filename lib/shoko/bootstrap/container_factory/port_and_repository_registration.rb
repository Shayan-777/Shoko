# frozen_string_literal: true

module Shoko
  module Bootstrap
    module ContainerFactory
      # Registers ports, adapters, and repositories in the DI container.
      module PortAndRepositoryRegistration
        # Register core port adapters.
        def register_core_ports(container)
          container.register_singleton(:text_metrics) do |c|
            Shoko::Adapters::Output::Terminal::TextMetricsPortAdapter.new(
              runtime_config: c.resolve(:runtime_config)
            )
          end
          container.register_singleton(:display_capabilities) do |_c|
            Shoko::Adapters::Output::Kitty::DisplayCapabilities.new
          end
          container.register_singleton(:instrumentation) { |c| c.resolve(:instrumentation_service) }
          container.register_factory(:async_executor) do |c|
            executor = (c.resolve(:background_worker) if c.registered?(:background_worker))
            executor || Shoko::Core::Services::InlineExecutor.new
          rescue Shoko::Error
            Shoko::Core::Services::InlineExecutor.new
          end

          # New hexagonal ports
          container.register_singleton(:config_storage) do |_c|
            Shoko::Adapters::Storage::ConfigStorageAdapter.new
          end
          container.register_singleton(:book_finder) do |c|
            config_storage = c.resolve(:config_storage)
            Shoko::Adapters::BookSources::BookFinder.new(
              config_root: config_storage.config_dir,
              cache_writer: Shoko::Adapters::Storage::AtomicFileWriter,
              logger: c.resolve(:logger)
            )
          end

          container.register_singleton(:terminal_capabilities) do |_c|
            Shoko::Adapters::Output::TerminalCapabilitiesAdapter.new
          end
          container.register_singleton(:layout_metrics) do |_c|
            Shoko::Adapters::Output::Layout::LayoutMetricsAdapter.new
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
          container.register_singleton(:metadata_reader) do |c|
            Shoko::Adapters::BookSources::MetadataReaderAdapter.new(
              file_probe: c.resolve(:file_probe),
              path_ops: c.resolve(:path_ops),
              runtime_config: c.resolve(:runtime_config)
            )
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
            Shoko::Adapters::Ui::RenderingFactory.new
          end
          container.register_singleton(:book_cache_pipeline_factory) do |_c|
            Shoko::Adapters::Storage::BookCachePipelineFactoryAdapter.new
          end
        end

        # Register repository implementations
        def register_repositories(container)
          container.register_factory(:bookmark_repository) do |c|
            Shoko::Adapters::Storage::Repositories::BookmarkRepository.new(
              file_writer: c.resolve(:file_writer),
              logger: c.resolve(:logger)
            )
          end
          container.register_factory(:annotation_repository) do |c|
            Shoko::Adapters::Storage::Repositories::AnnotationRepository.new(
              file_writer: c.resolve(:file_writer),
              logger: c.resolve(:logger)
            )
          end
          container.register_factory(:progress_repository) do |c|
            Shoko::Adapters::Storage::Repositories::ProgressRepository.new(
              file_writer: c.resolve(:file_writer),
              logger: c.resolve(:logger)
            )
          end
        end

        # Register state management services
        def register_state_management(container, event_bus)
          container.register_singleton(:global_state) do |c|
            Shoko::Adapters::Runtime::SessionState::ObserverStateStore.new(
              event_bus,
              config_storage: c.resolve(:config_storage),
              terminal_capabilities: c.resolve(:terminal_capabilities),
              logger: c.resolve(:logger)
            )
          end
          container.register_factory(:state_store) { |c| c.resolve(:global_state) }
          register_hexagonal_adapters(container)
        end

        # Register hexagonal architecture port adapters
        def register_hexagonal_adapters(container)
          container.register_factory(:config_reader) do |c|
            Shoko::Adapters::Runtime::SessionState::ConfigReaderAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:state_writer) do |c|
            Shoko::Adapters::Runtime::SessionState::StateWriterAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:rendered_content_reader) do |c|
            Shoko::Adapters::Runtime::SessionState::RenderedContentReaderAdapter.new(
              c.resolve(:global_state),
              render_registry: c.resolve(:render_registry)
            )
          end
          container.register_factory(:reader_state_reader) do |c|
            Shoko::Adapters::Runtime::SessionState::ReaderStateReaderAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:reader_navigation_reader) { |c| c.resolve(:reader_state_reader) }
          container.register_factory(:dictionary_ui_session) do |c|
            Shoko::Adapters::Ui::Sessions::DictionaryUiSessionAdapter.new(
              reader_state_reader: c.resolve(:reader_state_reader),
              state_writer: c.resolve(:reader_state_writer),
              ui_component_factory: c.resolve(:ui_component_factory),
              logger: c.resolve(:logger)
            )
          end
          container.register_factory(:in_book_search_ui_session) do |c|
            Shoko::Adapters::Ui::Sessions::InBookSearchUiSessionAdapter.new(
              reader_state_reader: c.resolve(:reader_state_reader),
              state_writer: c.resolve(:reader_state_writer),
              ui_component_factory: c.resolve(:ui_component_factory),
              rendered_content_reader: c.resolve(:rendered_content_reader),
              logger: c.resolve(:logger)
            )
          end
          container.register_factory(:annotation_overlay_ui_session) do |c|
            Shoko::Adapters::Ui::Sessions::AnnotationOverlayUiSessionAdapter.new(
              reader_state_reader: c.resolve(:reader_state_reader),
              state_writer: c.resolve(:reader_state_writer),
              ui_component_factory: c.resolve(:ui_component_factory),
              rendered_content_reader: c.resolve(:rendered_content_reader),
              logger: c.resolve(:logger)
            )
          end
          container.register_factory(:annotation_editor_launcher) do |c|
            Shoko::Adapters::Ui::Sessions::AnnotationEditorLauncherAdapter.new(
              annotation_overlay_ui_session: c.resolve(:annotation_overlay_ui_session)
            )
          end
          container.register_factory(:ui_state_reader) do |c|
            Shoko::Adapters::Runtime::SessionState::UiStateReaderAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:observer_registry) do |c|
            Shoko::Adapters::Runtime::SessionState::ObserverRegistryAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:render_state_writer) do |c|
            Shoko::Adapters::Runtime::SessionState::RenderStateWriterAdapter.new(
              c.resolve(:global_state),
              render_registry: c.resolve(:render_registry),
              logger: c.resolve(:logger)
            )
          end
          container.register_factory(:sidebar_state_reader) do |c|
            Shoko::Adapters::Runtime::SessionState::SidebarStateReaderAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:menu_state_reader) do |c|
            Shoko::Adapters::Runtime::SessionState::MenuStateReaderAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:menu_state_writer) do |c|
            Shoko::Adapters::Runtime::SessionState::MenuStateWriterAdapter.new(c.resolve(:global_state))
          end
          container.register_factory(:pagination_state_writer) { |c| c.resolve(:state_writer) }
          container.register_factory(:reader_state_writer) { |c| c.resolve(:state_writer) }
          container.register_factory(:notification_writer) do |c|
            Shoko::Adapters::Runtime::SessionState::NotificationWriterAdapter.new(
              c.resolve(:global_state),
              text_sanitizer: c.resolve(:text_sanitizer)
            )
          end
          container.register_singleton(:command_bus) do |_c|
            Shoko::Application::UseCases::CommandBus.new
          end
          container.register_factory(:view_model_builder_factory) do |c|
            reader_state_reader = c.resolve(:reader_state_reader)
            config_reader = c.resolve(:config_reader)
            lambda { |doc|
              Shoko::Adapters::Ui::ViewModels::ReaderViewModelBuilder.new(
                reader_state_reader: reader_state_reader,
                config_reader: config_reader,
                doc: doc
              )
            }
          end
        end

        # Register library scanning services
        def register_library_services(container)
          container.register_singleton(:cached_library_repository) do |c|
            Shoko::Adapters::Storage::Repositories::CachedLibraryRepository.new(
              runtime_config: c.resolve(:runtime_config)
            )
          end
          container.register_factory(:library_scanner) do |c|
            Shoko::Adapters::BookSources::LibraryScanner.new(
              background_worker_builder: c.resolve(:background_worker_builder),
              logger: c.resolve(:logger),
              book_finder: c.resolve(:book_finder)
            )
          end
        end
      end
    end
  end
end
