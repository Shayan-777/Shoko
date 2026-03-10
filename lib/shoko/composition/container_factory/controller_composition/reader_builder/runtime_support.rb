# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderBuilder
          module_function

          def prepare_reader_runtime_inputs(resolved)
            worker = resolved[:worker] || build_background_worker(
              background_worker_builder: resolved[:background_worker_builder],
              logger: resolved[:logger],
              name: 'reader-runtime'
            )

            resolved.merge(
              worker: worker,
              async_executor: prefer_worker_executor(async_executor: resolved[:async_executor], worker: worker),
              reader_lifecycle_factory: build_reader_lifecycle_factory,
              pending_jump_handler_factory: build_pending_jump_handler_factory(resolved[:reader_session_store]),
              pagination_coordinator_factory: build_pagination_coordinator_factory,
              in_book_search_service: build_in_book_search_service(
                document: resolved[:document],
                logger: resolved[:logger],
                page_calculator: resolved[:page_calculator],
                config_reader: resolved[:config_reader]
              )
            )
          end

          def sync_reader_launch_state!(resolved)
            session_context = resolved[:session_context]
            return unless session_context

            session_context.set_preloaded_document(resolved[:document]) if resolved[:document]
            session_context.set_background_worker(resolved[:worker]) if resolved[:worker]
          end

          def build_reader_ui_dependencies(resolved)
            Shoko::Adapters::Ui::ReaderUiDependencies.new(
              observer_registry: resolved[:observer_registry],
              terminal_service: resolved[:terminal_service],
              ui_state_reader: resolved[:ui_state_reader],
              reader_state_reader: resolved[:reader_state_reader],
              sidebar_state_reader: resolved[:sidebar_state_reader],
              config_reader: resolved[:config_reader],
              render_state_writer: resolved[:render_state_writer],
              rendered_content_reader: resolved[:rendered_content_reader],
              notification_service: resolved[:notification_service],
              logger: resolved[:logger],
              coordinate_service: resolved[:coordinate_service],
              view_model_builder_factory: resolved[:view_model_builder_factory],
              layout_service: resolved[:layout_service],
              layout_metrics: resolved[:layout_metrics],
              page_calculator: resolved[:page_calculator],
              wrapping_service: resolved[:wrapping_service],
              formatting_service: resolved[:formatting_service],
              kitty_image_renderer: resolved[:kitty_image_renderer],
              runtime_config: resolved[:runtime_config],
              reader_launch_state: resolved[:session_context],
              document: resolved[:document],
              annotation_service: resolved[:annotation_service]
            )
          end

          def build_reader_lifecycle_factory
            lambda do |controller, **kwargs|
              Shoko::Adapters::Input::Controllers::Reader::LifecycleRunner.new(controller, **kwargs)
            end
          end
          private_class_method :build_reader_lifecycle_factory

          def build_pending_jump_handler_factory(reader_session_store)
            lambda do |**kwargs|
              Shoko::Application::PendingJumpHandler.new(
                reader_session_store: reader_session_store,
                annotation_editor_launcher: kwargs[:annotation_editor_launcher],
                rendered_content_reader: kwargs[:rendered_content_reader],
                navigation_service: kwargs[:navigation_service],
                selection_service: kwargs[:selection_service],
                coordinate_service: kwargs[:coordinate_service]
              )
            end
          end
          private_class_method :build_pending_jump_handler_factory

          def build_pagination_coordinator_factory
            lambda do |**kwargs|
              Shoko::Application::Services::Pagination::PaginationCoordinator.new(**kwargs)
            end
          end
          private_class_method :build_pagination_coordinator_factory

          def build_in_book_search_service(document:, logger:, page_calculator:, config_reader:)
            Shoko::Core::Services::InBookSearchService.new(
              document: document,
              logger: logger,
              page_calculator: page_calculator,
              config_reader: config_reader
            )
          end
          private_class_method :build_in_book_search_service
        end
      end
    end
  end
end
