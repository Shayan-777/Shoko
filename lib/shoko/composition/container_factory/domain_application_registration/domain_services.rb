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
            register_translation_services(container)
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
              require_relative '../../../application/services/reader/navigation_service'

              Shoko::Application::Services::Reader::NavigationService.new(
                app_config_store: c.resolve(:app_config_store),
                reader_session_store: c.resolve(:reader_session_store),
                reader_state_reader: lazy_container_service(c, :reader_state_reader),
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
              require_relative '../../../application/services/reader/bookmark_service'

              Shoko::Application::Services::Reader::BookmarkService.new(
                bookmark_repository: c.resolve(:bookmark_repository),
                domain_event_bus: c.resolve(:domain_event_bus),
                domain_event_factory: c.resolve(:domain_event_factory),
                app_config_store: c.resolve(:app_config_store),
                reader_session_store: c.resolve(:reader_session_store),
                reader_state_reader: lazy_container_service(c, :reader_state_reader),
                reader_runtime_context: c.resolve(:reader_runtime_context),
                page_calculator: c.resolve(:page_calculator),
                layout_service: c.resolve(:layout_service),
                logger: c.resolve(:logger)
              )
            end
          end

          def register_page_calculator(container)
            container.register_singleton(:page_calculator) do |c|
              require_relative '../../../application/services/pagination/page_calculator_service'

              Shoko::Application::Services::Pagination::PageCalculatorService.new(**page_calculator_dependencies(c))
            end
          end

          def register_coordinate_service(container)
            container.register_factory(:coordinate_service) do |c|
              require_relative '../../../application/services/coordinate_service'

              Shoko::Application::Services::CoordinateService.new(logger: c.resolve(:logger))
            end
          end

          def register_reader_document_locator(container)
            container.register_factory(:reader_document_locator) do |c|
              require_relative '../../../adapters/storage/reader_document_locator'

              Shoko::Adapters::Storage::ReaderDocumentLocator.new(
                cache_pointer_resolver: c.resolve(:cache_pointer_resolver),
                path_ops: c.resolve(:path_ops),
                logger: c.resolve(:logger)
              )
            end
          end

          def register_popup_position_service(container)
            container.register_factory(:popup_position_service) do |c|
              require_relative '../../../application/services/popup_position_service'

              Shoko::Application::Services::PopupPositionService.new(
                reader_runtime_context: c.resolve(:reader_runtime_context)
              )
            end
          end

          def register_selection_service(container)
            container.register_factory(:selection_service) do |c|
              require_relative '../../../application/services/selection_service'

              Shoko::Application::Services::SelectionService.new(
                coordinate_service: c.resolve(:coordinate_service),
                logger: c.resolve(:logger)
              )
            end
          end

          def register_layout_service(container)
            container.register_factory(:layout_service) do |_c|
              require_relative '../../../application/services/layout_service'

              Shoko::Application::Services::LayoutService.new
            end
          end

          def register_chapter_cache_factory(container)
            container.register_singleton(:chapter_cache_factory) do |_c|
              lambda do |text_metrics:|
                require_relative '../../../core/services/pagination/internal/chapter_cache'

                Shoko::Core::Services::Pagination::Internal::ChapterCache.new(text_metrics: text_metrics)
              end
            end
          end

          def register_annotation_services(container)
            register_core_annotation_service(container)
            register_reader_annotation_service(container)
          end

          def register_dictionary_services(container)
            register_dictionary_lookup_service(container)
            register_dictionary_repository_service(container)
          end

          def register_translation_services(container)
            container.register_factory(:translation_service) do |c|
              require_relative '../../../core/services/translation_service'

              Shoko::Core::Services::TranslationService.new(
                translation_repository: c.resolve(:translation_repository),
                logger: c.resolve(:logger)
              )
            end
          end

          def register_dictionary_lookup_service(container)
            container.register_factory(:dictionary_service) do |c|
              require_relative '../../../core/services/dictionary_service'

              Shoko::Core::Services::DictionaryService.new(
                dictionary_repository: c.resolve(:dictionary_repository),
                config_reader: c.resolve(:app_config_store),
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
            require_relative '../../../adapters/storage/sqlite_dictionary_adapter'

            config_reader = container.resolve(:app_config_store)
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

          def page_calculator_dependencies(container)
            {
              text_metrics: container.resolve(:text_metrics),
              display_capabilities: container.resolve(:display_capabilities),
              instrumentation: container.resolve(:instrumentation),
              config_reader: container.resolve(:app_config_store),
              layout_service: container.resolve(:layout_service),
              pagination_cache: container.resolve(:pagination_cache),
              wrapping_service: container.resolve(:wrapping_service),
              formatting_service: container.resolve(:formatting_service),
              logger: container.resolve(:logger),
            }
          end

          def register_core_annotation_service(container)
            container.register_factory(:core_annotation_service) do |c|
              require_relative '../../../core/services/annotation_service'

              Shoko::Core::Services::AnnotationService.new(
                annotation_repository: c.resolve(:annotation_repository),
                domain_event_bus: c.resolve(:domain_event_bus),
                domain_event_factory: c.resolve(:domain_event_factory),
                logger: c.resolve(:logger)
              )
            end
          end

          def register_reader_annotation_service(container)
            container.register_factory(:annotation_service) do |c|
              require_relative '../../../application/services/reader/annotation_state_service'

              Shoko::Application::Services::Reader::AnnotationStateService.new(
                core_annotation_service: c.resolve(:core_annotation_service),
                reader_session_store: c.resolve(:reader_session_store),
                logger: c.resolve(:logger)
              )
            end
          end
        end
      end
    end
  end
end
