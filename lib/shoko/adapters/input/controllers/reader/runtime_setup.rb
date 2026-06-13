# frozen_string_literal: true

require_relative 'input_router'
require_relative 'startup_loader'
require_relative 'render_metrics'
require_relative 'runtime_types'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Builds the reader startup/runtime wiring outside the controller body.
          class RuntimeSetup
            SetupResult = Data.define(
              :document,
              :startup_loader,
              :pending_jump_handler,
              :lifecycle,
              :controllers,
              :pagination_coordinator,
              :render_coordinator,
              :input_router,
              :render_metrics,
              :intent_handler
            )

            def initialize(controller:, epub_path:, boot:, startup:, runtime_components_factory:)
              @controller = controller
              @epub_path = epub_path
              @boot = boot.validate!
              @startup = startup.validate!
              @runtime_components_factory = runtime_components_factory
            end

            def call
              lifecycle = build_reader_lifecycle
              lifecycle.ensure_background_worker

              startup_loader = build_startup_loader
              document = load_initial_document(startup_loader)
              components = build_runtime_components!
              pending_jump_handler = build_pending_jump_handler(components.anchor_resolver)

              build_setup_result(
                document: document,
                startup_loader: startup_loader,
                pending_jump_handler: pending_jump_handler,
                lifecycle: lifecycle,
                components: components
              )
            end

            private

            def build_reader_lifecycle
              factory = @boot.reader_lifecycle_factory
              raise ArgumentError, 'reader_lifecycle_factory is required' if factory.nil?

              factory.call(
                @controller,
                terminal_session: @boot.terminal_session,
                background_worker: @boot.background_worker,
                background_worker_builder: @boot.background_worker_builder,
                async_executor: @boot.async_executor,
                instrumentation_service: @boot.instrumentation_service,
                logger: @controller.logger,
                pagination_cache_preloader: @boot.warmup_services&.pagination_cache_preloader,
                image_cache_warmup: @boot.warmup_services&.image_cache_warmup,
                kitty_image_renderer: @boot.warmup_services&.kitty_image_renderer
              )
            end

            def build_startup_loader
              Reader::StartupLoader.new(
                path: @epub_path,
                document_loader: @startup.document_loader,
                reader_launch_state: @startup.reader_launch_state,
                reader_session_mutator: @controller.reader_session_mutator,
                document_matches_path: ->(existing, target_path) { document_matches_path?(existing, target_path) },
                logger: @controller.logger
              )
            end

            def load_initial_document(startup_loader)
              target_path = canonical_reader_path(@controller.path)
              document = startup_loader.validate_preloaded_document(@startup.document, target_path)
              document ||= startup_loader.load_document(
                current_doc: document,
                on_loaded: ->(fresh) { document = fresh }
              )
              @startup.reader_launch_state&.preloaded_document = document if document
              @controller.reader_session_mutator.update_reader(book_path: @epub_path)
              # A validated preloaded document skips load_document above, so publish
              # its chapter count here too — chapter jumps (TOC, search landing)
              # validate against the session store's total_chapters.
              sync_total_chapters(document)
              document
            end

            def sync_total_chapters(document)
              return unless document

              @controller.reader_session_mutator.update_reader(total_chapters: document.chapter_count)
            end

            def build_runtime_components!
              raise ArgumentError, 'runtime_components_factory is required' if @runtime_components_factory.nil?

              components = @runtime_components_factory.call(@controller)
              return components if components.is_a?(RuntimeTypes::RuntimeComponents)

              raise ArgumentError, 'runtime_components_factory must return Reader::RuntimeTypes::RuntimeComponents'
            end

            def build_input_router(components)
              Reader::InputRouter.new(
                reader_state_reader: @controller.reader_state_reader,
                input_controller: components.input_controller,
                ui_controller: components.ui_controller,
                key_classifier: @startup.key_classifier
              )
            end

            def build_setup_result(document:, startup_loader:, pending_jump_handler:, lifecycle:, components:)
              SetupResult.new(
                document: document,
                startup_loader: startup_loader,
                pending_jump_handler: pending_jump_handler,
                lifecycle: lifecycle,
                controllers: controller_refs_for(components),
                pagination_coordinator: components.pagination_coordinator,
                render_coordinator: components.render_coordinator,
                input_router: build_input_router(components),
                render_metrics: build_render_metrics,
                intent_handler: @startup.intent_handler_factory.call(@controller)
              )
            end

            def controller_refs_for(components)
              RuntimeTypes::ControllerRefs.new(
                ui_controller: components.ui_controller,
                state_controller: components.state_controller,
                input_controller: components.input_controller
              )
            end

            def build_render_metrics
              Reader::RenderMetrics.new(
                instrumentation: @controller.instrumentation,
                metrics_start_time_reader: -> { @controller.metrics_start_time },
                document_reader: -> { @controller.doc },
                clock: @controller.clock
              )
            end

            def build_pending_jump_handler(anchor_resolver)
              factory = @startup.pending_jump_handler_factory
              raise ArgumentError, 'pending_jump_handler_factory is required' if factory.nil?

              factory.call(
                reader_state: @controller.reader_state_reader,
                annotation_editor_launcher: @startup.annotation_editor_launcher,
                navigation_service: @controller.navigation_service,
                anchor_resolver: anchor_resolver
              )
            end

            def canonical_reader_path(path)
              locator = @startup.reader_document_locator
              return path unless locator

              locator.canonical_reader_path(path)
            end

            def document_matches_path?(document, target_path)
              locator = @startup.reader_document_locator
              return false unless locator

              locator.document_matches_path?(document, target_path)
            end
          end
        end
      end
    end
  end
end
