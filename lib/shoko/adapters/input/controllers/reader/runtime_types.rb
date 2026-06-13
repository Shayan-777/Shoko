# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Shared mutable runtime state holders for the reader controller.
          module RuntimeTypes
            Context = Struct.new(:path, :doc, :metrics_start_time)
            Services = Struct.new(:page_calculator, :terminal_service, :clipboard_service, :instrumentation)
            References = Struct.new(
              :navigation_service,
              :bookmark_service,
              :popup_position_service,
              :logger,
              :process_control,
              :clock,
              :selection_service,
              :wrapping_service,
              :rendered_content_reader,
              :annotation_service,
              :render_registry,
              :coordinate_service,
              :reader_state_reader,
              :reader_session_mutator,
              :ui_state_reader,
              :config_reader
            )
            ControllerRefs = Struct.new(:ui_controller, :state_controller, :input_controller)
            Coordinators = Struct.new(:lifecycle, :pagination_coordinator, :render_coordinator)
            RuntimeComponents = Struct.new(:ui_controller,
                                           :state_controller,
                                           :input_controller,
                                           :pagination_coordinator,
                                           :render_coordinator,
                                           :anchor_resolver)

            module_function

            def context_for(epub_path)
              Context.new(path: epub_path, doc: nil, metrics_start_time: nil)
            end

            def services_for(core)
              Services.new(
                page_calculator: core.page_calculator,
                terminal_service: core.terminal_service,
                clipboard_service: core.clipboard_service,
                instrumentation: core.instrumentation
              )
            end

            def references_for(core:, state:, services:)
              References.new(**service_references(core, services), **state_references(state))
            end

            def service_references(core, services)
              {
                navigation_service: services.navigation_service,
                bookmark_service: services.bookmark_service,
                popup_position_service: services.popup_position_service,
                logger: core.logger,
                process_control: core.process_control,
                clock: core.clock,
                rendered_content_reader: services.rendered_content_reader,
                annotation_service: services.annotation_service,
                render_registry: services.render_registry,
                coordinate_service: services.coordinate_service,
              }
            end

            def state_references(state)
              {
                selection_service: state.selection_service,
                wrapping_service: state.wrapping_service,
                reader_state_reader: state.reader_state_reader,
                reader_session_mutator: state.reader_session_mutator,
                ui_state_reader: state.ui_state_reader,
                config_reader: state.config_reader,
              }
            end
          end
        end
      end
    end
  end
end
