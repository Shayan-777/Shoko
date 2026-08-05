# frozen_string_literal: true

require 'shoko/application/pending_jump_handler'
require 'shoko/application/ports/outbound/background_worker_builder'
require 'shoko/application/services/pagination/pagination_coordinator'
require 'shoko/application/use_cases/reader_intent_handler'
require 'shoko/core/services/in_book_search_service'
require 'shoko/adapters/input/controllers/dependencies/reader_mouse_dependencies'
require 'shoko/adapters/input/controllers/dependencies/reader_controller_core_dependencies'
require 'shoko/adapters/input/controllers/dependencies/reader_controller_service_dependencies'
require 'shoko/adapters/input/controllers/dependencies/reader_controller_state_dependencies'
require 'shoko/adapters/input/controllers/dependencies/reader_runtime_boot_dependencies'
require 'shoko/adapters/input/controllers/dependencies/reader_runtime_startup_dependencies'
require 'shoko/adapters/input/controllers/dependencies/reader_warmup_services'
require 'shoko/adapters/input/controllers/reader_controller'
require 'shoko/adapters/input/controllers/reader/intent_runtime_bridge'
require 'shoko/adapters/input/controllers/reader/lifecycle_runner'
require 'shoko/adapters/ui/rendering/line/render_dependencies'
require_relative 'reader_runtime_assembler'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        # Builds the fully-wired reader controller: resolves the container
        # graph, prepares runtime-only dependencies, constructs the staged
        # dependency groups, and instantiates the concrete controller.
        # Deliberately one flat, boring wiring file (constitution section 7).
        module ReaderBuilder
          # Typed reader builder inputs resolved directly from the container and launch state.
          ResolvedDependencies = Data.define(
            :reader_launch_state,
            :document,
            :worker,
            :input_system_factory,
            :terminal_service,
            :terminal_session,
            :page_calculator,
            :clipboard_service,
            :layout_service,
            :rendering_factory,
            :dictionary_ui_session,
            :in_book_search_ui_session,
            :toc_ui_session,
            :translator_ui_session,
            :notes_ui_session,
            :annotation_overlay_ui_session,
            :annotation_editor_launcher,
            :app_config_store,
            :reader_state_reader,
            :reader_session_store,
            :reader_view_state_store,
            :reader_pagination_store,
            :reader_session_mutator,
            :reader_runtime_context,
            :reader_component_registry,
            :clock,
            :observer_registry,
            :instrumentation,
            :navigation_service,
            :bookmark_service,
            :key_classifier,
            :selection_service,
            :wrapping_service,
            :rendered_content_reader,
            :annotation_service,
            :document_loader,
            :coordinate_service,
            :reader_document_locator,
            :popup_position_service,
            :notification_service,
            :ui_component_factory,
            :layout_metrics,
            :translation_service,
            :dictionary_service,
            :dictionary_catalog_service,
            :settings_service,
            :dictionary_availability,
            :dictionary_storage,
            :runtime_config,
            :formatting_service,
            :background_worker_builder,
            :progress_repository,
            :bookmark_repository,
            :pagination_cache,
            :notification_writer,
            :async_executor,
            :display_capabilities,
            :process_control,
            :instrumentation_service,
            :pagination_cache_preloader,
            :render_state_writer,
            :logger,
            :view_model_builder_factory,
            :kitty_image_renderer,
            :image_cache_warmup
          ) do
            def self.resolve(container:, preloaded_document:, background_worker:)
              launch_state = container.resolve(:reader_launch_state)

              new(
                reader_launch_state: launch_state,
                document: preloaded_document || launch_state&.preloaded_document,
                worker: background_worker || launch_state&.background_worker,
                **container_fields.to_h { |field| [field, container.resolve(field)] }
              )
            end

            def self.container_fields
              members - %i[reader_launch_state document worker]
            end
            private_class_method :container_fields
          end

          # Resolved inputs plus the runtime-only dependencies built after the
          # container graph is resolved.
          PreparedDependencies = Data.define(
            *ResolvedDependencies.members,
            :reader_lifecycle_factory,
            :pending_jump_handler_factory,
            :pagination_coordinator_factory,
            :in_book_search_service
          )

          # Staged reader controller dependency groups.
          ControllerDependencies = Data.define(
            :core,
            :state,
            :services,
            :runtime_boot,
            :runtime_startup,
            :mouse_support
          )

          OVERRIDDEN_FIELDS = %i[worker async_executor].freeze

          RENDER_DEPENDENCY_FIELDS = {
            observer_registry: :observer_registry,
            reader_state_reader: :reader_state_reader,
            render_state_writer: :render_state_writer,
            rendered_content_reader: :rendered_content_reader,
            logger: :logger,
            layout_service: :layout_service,
            layout_metrics: :layout_metrics,
            page_calculator: :page_calculator,
            wrapping_service: :wrapping_service,
            formatting_service: :formatting_service,
            kitty_image_renderer: :kitty_image_renderer,
            runtime_config: :runtime_config,
            reader_launch_state: :reader_launch_state,
            document: :document,
          }.freeze

          SERVICE_CONTEXT_FIELDS = {
            navigation_service: :navigation_service,
            bookmark_service: :bookmark_service,
            annotation_service: :annotation_service,
            coordinate_service: :coordinate_service,
            notification_service: :notification_service,
            selection_service: :selection_service,
            translation_service: :translation_service,
            dictionary_service: :dictionary_service,
            dictionary_catalog_service: :dictionary_catalog_service,
            settings_service: :settings_service,
            dictionary_availability: :dictionary_availability,
            dictionary_storage: :dictionary_storage,
            progress_repository: :progress_repository,
            bookmark_repository: :bookmark_repository,
            pagination_cache: :pagination_cache,
            in_book_search_service: :in_book_search_service,
            reader_state_reader: :reader_state_reader,
          }.freeze

          module_function

          def build_controller(container:, epub_path:, preloaded_document:, background_worker:)
            resolved = ResolvedDependencies.resolve(
              container: container,
              preloaded_document: preloaded_document,
              background_worker: background_worker
            )
            prepared = prepare_runtime_dependencies(resolved)
            render_dependencies = build_render_dependencies(prepared)
            controller_dependencies = build_controller_dependencies(prepared)
            runtime_context = build_runtime_context(prepared, render_dependencies: render_dependencies)

            instantiate_reader_controller(
              epub_path: epub_path,
              prepared: prepared,
              controller_dependencies: controller_dependencies,
              runtime_context: runtime_context
            )
          end

          # ----- runtime preparation ------------------------------------------

          def prepare_runtime_dependencies(resolved)
            prepared = build_prepared_dependencies(resolved)
            sync_reader_launch_state!(
              prepared.reader_launch_state,
              document: prepared.document,
              worker: prepared.worker
            )
            prepared
          end
          private_class_method :prepare_runtime_dependencies

          def build_prepared_dependencies(resolved)
            worker = resolved.worker || build_background_worker(
              background_worker_builder: resolved.background_worker_builder,
              logger: resolved.logger,
              name: 'reader-runtime'
            )

            PreparedDependencies.new(
              **resolved.to_h.except(*OVERRIDDEN_FIELDS),
              **prepared_runtime_attributes(resolved, worker)
            )
          end
          private_class_method :build_prepared_dependencies

          def prepared_runtime_attributes(resolved, worker)
            {
              worker: worker,
              async_executor: prefer_worker_executor(async_executor: resolved.async_executor, worker: worker),
              reader_lifecycle_factory: reader_lifecycle_factory,
              pending_jump_handler_factory: pending_jump_handler_factory(resolved.reader_session_store),
              pagination_coordinator_factory: pagination_coordinator_factory,
              in_book_search_service: build_in_book_search_service(resolved),
            }
          end
          private_class_method :prepared_runtime_attributes

          def build_in_book_search_service(resolved)
            launch_state = resolved.reader_launch_state
            Shoko::Core::Services::InBookSearchService.new(
              document: resolved.document,
              logger: resolved.logger,
              chapter_formatter: resolved.formatting_service,
              # Cached books load their document after this build (the
              # startup loader publishes it); bind late or search scans nil.
              document_provider: -> { launch_state&.preloaded_document }
            )
          end
          private_class_method :build_in_book_search_service

          def build_background_worker(background_worker_builder:, logger:, name:)
            return nil unless background_worker_builder

            unless background_worker_builder.is_a?(Shoko::Application::Ports::Outbound::BackgroundWorkerBuilder)
              raise ArgumentError,
                    'background_worker_builder must implement Application::Ports::Outbound::BackgroundWorkerBuilder'
            end

            background_worker_builder.build(logger: logger, name: name)
          end
          private_class_method :build_background_worker

          def prefer_worker_executor(async_executor:, worker:)
            return async_executor unless worker
            return worker if async_executor.nil?
            return worker if async_executor&.synchronous?

            async_executor
          end
          private_class_method :prefer_worker_executor

          def reader_lifecycle_factory
            lambda do |controller, **kwargs|
              Shoko::Adapters::Input::Controllers::Reader::LifecycleRunner.new(controller, **kwargs)
            end
          end
          private_class_method :reader_lifecycle_factory

          def pending_jump_handler_factory(reader_session_store)
            lambda do |**kwargs|
              Shoko::Application::PendingJumpHandler.new(
                reader_session_store: reader_session_store,
                annotation_editor_launcher: kwargs[:annotation_editor_launcher],
                navigation_service: kwargs[:navigation_service],
                anchor_resolver: kwargs[:anchor_resolver]
              )
            end
          end
          private_class_method :pending_jump_handler_factory

          def pagination_coordinator_factory
            lambda do |**kwargs|
              Shoko::Application::Services::Pagination::PaginationCoordinator.new(**kwargs)
            end
          end
          private_class_method :pagination_coordinator_factory

          def sync_reader_launch_state!(launch_state, document:, worker:)
            return unless launch_state

            launch_state.preloaded_document = document if document
            launch_state.background_worker = worker if worker
          end
          private_class_method :sync_reader_launch_state!

          # ----- dependency construction --------------------------------------

          # The render dependencies are built here, fully formed, instead of
          # shipping a wider ReaderUiDependencies bag for the render
          # coordinator to repackage into this exact record at draw time.
          def build_render_dependencies(prepared)
            Shoko::Adapters::Ui::Components::Reading::RenderDependencies.new(
              **extract_attributes(prepared, RENDER_DEPENDENCY_FIELDS),
              config_reader: prepared.app_config_store,
              terminal_output: prepared.terminal_service.output
            )
          end
          private_class_method :build_render_dependencies

          def build_controller_dependencies(prepared)
            ControllerDependencies.new(
              core: build_core_dependencies(prepared),
              state: build_state_dependencies(prepared),
              services: build_service_dependencies(prepared),
              runtime_boot: build_runtime_boot_dependencies(prepared),
              runtime_startup: build_runtime_startup_dependencies(prepared),
              mouse_support: build_mouse_support_dependencies(prepared)
            )
          end
          private_class_method :build_controller_dependencies

          def build_core_dependencies(prepared)
            deps::ReaderControllerCoreDependencies.new(
              page_calculator: prepared.page_calculator,
              terminal_service: prepared.terminal_service,
              clipboard_service: prepared.clipboard_service,
              instrumentation: prepared.instrumentation,
              logger: prepared.logger,
              clock: prepared.clock,
              process_control: prepared.process_control
            ).validate!
          end
          private_class_method :build_core_dependencies

          def build_state_dependencies(prepared)
            deps::ReaderControllerStateDependencies.new(
              observer_registry: prepared.observer_registry,
              config_reader: prepared.app_config_store,
              reader_state_reader: prepared.reader_state_reader,
              reader_session_mutator: prepared.reader_session_mutator,
              ui_state_reader: prepared.reader_runtime_context,
              selection_service: prepared.selection_service,
              wrapping_service: prepared.wrapping_service
            ).validate!
          end
          private_class_method :build_state_dependencies

          def build_service_dependencies(prepared)
            deps::ReaderControllerServiceDependencies.new(
              navigation_service: prepared.navigation_service,
              bookmark_service: prepared.bookmark_service,
              popup_position_service: prepared.popup_position_service,
              rendered_content_reader: prepared.rendered_content_reader,
              annotation_service: prepared.annotation_service,
              coordinate_service: prepared.coordinate_service
            ).validate!
          end
          private_class_method :build_service_dependencies

          def build_runtime_boot_dependencies(prepared)
            deps::ReaderRuntimeBootDependencies.new(
              reader_lifecycle_factory: prepared.reader_lifecycle_factory,
              terminal_session: prepared.terminal_session,
              background_worker: prepared.worker,
              background_worker_builder: prepared.background_worker_builder,
              async_executor: prepared.async_executor,
              instrumentation_service: prepared.instrumentation_service,
              warmup_services: build_warmup_services(prepared)
            ).validate!
          end
          private_class_method :build_runtime_boot_dependencies

          def build_warmup_services(prepared)
            deps::ReaderWarmupServices.new(
              pagination_cache_preloader: prepared.pagination_cache_preloader,
              image_cache_warmup: prepared.image_cache_warmup,
              kitty_image_renderer: prepared.kitty_image_renderer
            )
          end
          private_class_method :build_warmup_services

          def build_runtime_startup_dependencies(prepared)
            deps::ReaderRuntimeStartupDependencies.new(
              intent_handler_factory: reader_intent_handler_factory(prepared),
              pending_jump_handler_factory: prepared.pending_jump_handler_factory,
              document_loader: prepared.document_loader,
              reader_document_locator: prepared.reader_document_locator,
              reader_launch_state: prepared.reader_launch_state,
              document: prepared.document,
              annotation_editor_launcher: prepared.annotation_editor_launcher,
              key_classifier: prepared.key_classifier
            ).validate!
          end
          private_class_method :build_runtime_startup_dependencies

          def build_mouse_support_dependencies(prepared)
            deps::ReaderMouseDependencies.new(
              formatting_service: prepared.formatting_service,
              layout_service: prepared.layout_service,
              dictionary_availability: prepared.dictionary_availability,
              ui_component_factory: prepared.ui_component_factory,
              ui_state_reader: prepared.reader_runtime_context
            ).validate!
          end
          private_class_method :build_mouse_support_dependencies

          def reader_intent_handler_factory(prepared)
            lambda { |controller|
              build_reader_intent_handler(
                controller,
                reader_session_store: prepared.reader_session_store,
                reader_view_state_store: prepared.reader_view_state_store,
                reader_view_mutator: prepared.reader_session_mutator,
                app_config_store: prepared.app_config_store,
                notification_writer: prepared.notification_writer
              )
            }
          end
          private_class_method :reader_intent_handler_factory

          def build_reader_intent_handler(controller, reader_session_store:, reader_view_state_store:,
                                          reader_view_mutator:, app_config_store:, notification_writer:)
            runtime = Shoko::Adapters::Input::Controllers::Reader::IntentRuntimeBridge.new(
              reader_controller: controller
            )
            state_ports = {
              reader_session_store: reader_session_store, reader_view_state_store: reader_view_state_store,
              reader_view_mutator: reader_view_mutator, app_config_store: app_config_store,
              notification_writer: notification_writer
            }
            Shoko::Application::UseCases::ReaderIntentHandler.new(
              **reader_intent_handler_options(controller, runtime, state_ports)
            )
          end
          private_class_method :build_reader_intent_handler

          def reader_intent_handler_options(controller, runtime, state_ports)
            {
              navigation_service: controller.navigation_service,
              bookmark_service: controller.bookmark_service,
              **state_ports,
              **reader_runtime_control_options(runtime),
              annotation_service: controller.annotation_service,
            }
          end
          private_class_method :reader_intent_handler_options

          def reader_runtime_control_options(runtime)
            %i[
              reader_overlay_control reader_popup_control reader_dictionary_control reader_search_control
              reader_toc_control reader_translator_control reader_notes_control reader_annotation_editor_control
              reader_lifecycle_control application_exit_control
            ].to_h { |key| [key, runtime] }
          end
          private_class_method :reader_runtime_control_options

          def deps
            Shoko::Adapters::Input::Controllers::Dependencies
          end
          private_class_method :deps

          # ----- runtime context ----------------------------------------------

          def build_runtime_context(prepared, render_dependencies:)
            ReaderRuntimeAssembler::RuntimeContext.new(
              platform: build_platform_context(prepared),
              state: build_state_context(prepared),
              ui: build_ui_context(prepared),
              services: build_service_context(prepared),
              render_dependencies: render_dependencies,
              view_model_builder_factory: prepared.view_model_builder_factory
            )
          end
          private_class_method :build_runtime_context

          def build_platform_context(prepared)
            launch_state = prepared.reader_launch_state
            ReaderRuntimeAssembler::ReaderPlatformContext.new(
              doc: prepared.document,
              # Direct file opens load the document after the reader graph is
              # built; consumers that need it late-bind through this provider.
              document_provider: -> { launch_state&.preloaded_document },
              terminal_service: prepared.terminal_service,
              terminal_session: prepared.terminal_session,
              page_calculator: prepared.page_calculator,
              clock: prepared.clock,
              process_control: prepared.process_control,
              async_executor: prepared.async_executor,
              display_capabilities: prepared.display_capabilities,
              instrumentation: prepared.instrumentation,
              logger: prepared.logger
            )
          end
          private_class_method :build_platform_context

          def build_state_context(prepared)
            ReaderRuntimeAssembler::ReaderStateContext.new(
              reader_session_store: prepared.reader_session_store,
              reader_session_mutator: prepared.reader_session_mutator,
              app_config_store: prepared.app_config_store,
              observer_registry: prepared.observer_registry,
              reader_runtime_context: prepared.reader_runtime_context,
              rendered_content_reader: prepared.rendered_content_reader,
              notification_writer: prepared.notification_writer,
              reader_component_registry: prepared.reader_component_registry
            )
          end
          private_class_method :build_state_context

          def build_ui_context(prepared)
            ReaderRuntimeAssembler::ReaderUiContext.new(
              layout_service: prepared.layout_service,
              layout_metrics: prepared.layout_metrics,
              wrapping_service: prepared.wrapping_service,
              formatting_service: prepared.formatting_service,
              ui_component_factory: prepared.ui_component_factory,
              input_system_factory: prepared.input_system_factory,
              rendering_factory: prepared.rendering_factory,
              dictionary_ui_session: prepared.dictionary_ui_session,
              in_book_search_ui_session: prepared.in_book_search_ui_session,
              toc_ui_session: prepared.toc_ui_session,
              translator_ui_session: prepared.translator_ui_session,
              notes_ui_session: prepared.notes_ui_session,
              annotation_overlay_ui_session: prepared.annotation_overlay_ui_session
            )
          end
          private_class_method :build_ui_context

          def build_service_context(prepared)
            ReaderRuntimeAssembler::ReaderServiceContext.new(
              **extract_attributes(prepared, SERVICE_CONTEXT_FIELDS),
              reader_view_state_store: prepared.reader_view_state_store,
              reader_pagination_store: prepared.reader_pagination_store
            )
          end
          private_class_method :build_service_context

          def extract_attributes(prepared, field_map)
            prepared_hash = prepared.to_h
            field_map.transform_values { |source| prepared_hash.fetch(source) }
          end
          private_class_method :extract_attributes

          # ----- controller instantiation -------------------------------------

          def instantiate_reader_controller(epub_path:, prepared:, controller_dependencies:, runtime_context:)
            Shoko::Adapters::Input::Controllers::ReaderController.new(
              epub_path,
              core: controller_dependencies.core,
              state: controller_dependencies.state,
              services: controller_dependencies.services,
              runtime_boot: controller_dependencies.runtime_boot,
              runtime_startup: controller_dependencies.runtime_startup,
              mouse_support: controller_dependencies.mouse_support,
              render_state_writer: prepared.render_state_writer,
              mouse_handler: prepared.input_system_factory.create_mouse_handler,
              runtime_components_factory: build_runtime_components_factory(runtime_context)
            )
          end
          private_class_method :instantiate_reader_controller

          def build_runtime_components_factory(runtime_context)
            lambda do |controller_instance|
              ReaderRuntimeAssembler.call(controller: controller_instance, context: runtime_context)
            end
          end
          private_class_method :build_runtime_components_factory
        end
      end
    end
  end
end
