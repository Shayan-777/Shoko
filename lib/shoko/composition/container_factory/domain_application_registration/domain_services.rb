# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module DomainApplicationRegistration
        # Domain service registration surface.
        module DomainServices
          def register_domain_services(container)
            register_domain_event_factory(container)
            register_reader_domain_services(container)
            register_annotation_services(container)
            register_dictionary_services(container)
          end

          private

          def register_domain_event_factory(container)
            container.register_singleton(:domain_event_factory) do |c|
              Shoko::Core::Events::EventFactory.new(
                wall_clock: c.resolve(:wall_clock),
                id_generator: c.resolve(:id_generator)
              )
            end
          end

          def register_reader_domain_services(container)
            register_navigation_service(container)
            register_bookmark_service(container)
            register_page_calculator(container)
            register_coordinate_service(container)
            register_reader_document_locator(container)
            register_popup_position_service(container)
            register_selection_service(container)
            register_layout_service(container)
            register_chapter_cache_factory(container)
          end

          def register_navigation_service(container)
            container.register_factory(:navigation_service) do |c|
              Shoko::Application::Services::Reader::NavigationService.new(
                app_config_store: c.resolve(:app_config_store),
                reader_session_store: c.resolve(:reader_session_store),
                reader_runtime_context: c.resolve(:reader_runtime_context),
                page_calculator: c.resolve(:page_calculator),
                layout_service: c.resolve(:layout_service),
                wrapped_lines_provider: c.resolve(:wrapped_lines_provider),
                logger: c.resolve(:logger)
              )
            end
          end

          def register_bookmark_service(container)
            container.register_factory(:bookmark_service) do |c|
              Shoko::Application::Services::Reader::BookmarkService.new(
                bookmark_repository: c.resolve(:bookmark_repository),
                domain_event_bus: c.resolve(:domain_event_bus),
                domain_event_factory: c.resolve(:domain_event_factory),
                app_config_store: c.resolve(:app_config_store),
                reader_session_store: c.resolve(:reader_session_store),
                reader_runtime_context: c.resolve(:reader_runtime_context),
                page_calculator: c.resolve(:page_calculator),
                layout_service: c.resolve(:layout_service),
                logger: c.resolve(:logger)
              )
            end
          end

          def register_page_calculator(container)
            container.register_singleton(:page_calculator) do |c|
              line_wrapper = c.resolve(:wrapping_service)
              chapter_formatter = c.resolve(:formatting_service)
              Shoko::Application::Services::Pagination::PageCalculatorService.new(
                text_metrics: c.resolve(:text_metrics),
                display_capabilities: c.resolve(:display_capabilities),
                instrumentation: c.resolve(:instrumentation),
                config_reader: c.resolve(:config_view),
                layout_service: c.resolve(:layout_service),
                pagination_cache: c.resolve(:pagination_cache),
                wrapping_service: line_wrapper,
                formatting_service: chapter_formatter,
                logger: c.resolve(:logger)
              )
            end
          end

          def register_coordinate_service(container)
            container.register_factory(:coordinate_service) do |c|
              Shoko::Application::Services::CoordinateService.new(logger: c.resolve(:logger))
            end
          end

          def register_reader_document_locator(container)
            container.register_factory(:reader_document_locator) do |c|
              Shoko::Adapters::Storage::ReaderDocumentLocator.new(
                cache_pointer_resolver: c.resolve(:cache_pointer_resolver),
                path_ops: c.resolve(:path_ops),
                logger: c.resolve(:logger)
              )
            end
          end

          def register_popup_position_service(container)
            container.register_factory(:popup_position_service) do |c|
              Shoko::Application::Services::PopupPositionService.new(
                reader_runtime_context: c.resolve(:reader_runtime_context)
              )
            end
          end

          def register_selection_service(container)
            container.register_factory(:selection_service) do |c|
              Shoko::Application::Services::SelectionService.new(
                coordinate_service: c.resolve(:coordinate_service),
                logger: c.resolve(:logger)
              )
            end
          end

          def register_layout_service(container)
            container.register_factory(:layout_service) { |_c| Shoko::Application::Services::LayoutService.new }
          end

          def register_chapter_cache_factory(container)
            container.register_singleton(:chapter_cache_factory) do |_c|
              lambda do |text_metrics:|
                Shoko::Core::Services::Pagination::Internal::ChapterCache.new(text_metrics: text_metrics)
              end
            end
          end

          def register_annotation_services(container)
            container.register_factory(:core_annotation_service) do |c|
              Shoko::Core::Services::AnnotationService.new(
                annotation_repository: c.resolve(:annotation_repository),
                domain_event_bus: c.resolve(:domain_event_bus),
                domain_event_factory: c.resolve(:domain_event_factory),
                logger: c.resolve(:logger)
              )
            end

            container.register_factory(:annotation_service) do |c|
              Shoko::Application::Services::Reader::AnnotationStateService.new(
                core_annotation_service: c.resolve(:core_annotation_service),
                reader_session_store: c.resolve(:reader_session_store),
                logger: c.resolve(:logger)
              )
            end
          end

          def register_dictionary_services(container)
            register_dictionary_lookup_service(container)
            register_dictionary_repository_service(container)
          end

          def register_dictionary_lookup_service(container)
            container.register_factory(:dictionary_service) do |c|
              Shoko::Core::Services::DictionaryService.new(
                dictionary_repository: c.resolve(:dictionary_repository),
                config_reader: c.resolve(:config_view),
                logger: c.resolve(:logger)
              )
            end
          end

          def register_dictionary_repository_service(container)
            container.register_factory(:dictionary_repository) do |c|
              build_dictionary_repository(c)
            end
          end

          def build_dictionary_repository(container)
            config_reader = container.resolve(:config_view)
            runtime_config = container.resolve(:runtime_config)
            backend_name = config_reader&.dictionary_backend.to_s.downcase
            runtime_override = runtime_config&.dictionary_backend_override
            unless dictionary_backend_enabled?(backend_name: backend_name, runtime_override: runtime_override)
              return nil
            end

            dict_path = config_reader&.dictionary_path
            Shoko::Adapters::Storage::SqliteDictionaryAdapter.new(
              databases_path: dict_path,
              logger: container.resolve(:logger)
            )
          end

          def dictionary_backend_enabled?(backend_name:, runtime_override:)
            backend_name != 'disabled' && runtime_override != 'disabled'
          end
        end
      end
    end
  end
end
