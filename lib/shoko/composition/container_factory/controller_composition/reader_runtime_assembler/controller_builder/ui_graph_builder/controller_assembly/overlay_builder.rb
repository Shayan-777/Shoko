# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderRuntimeAssembler
          module ControllerBuilder
            module UiGraphBuilder
              module ControllerAssembly
                module OverlayBuilder
                  module_function

                  def build_annotation(build_context)
                    deps = Shoko::Adapters::Input::Controllers::AnnotationOverlayController::Dependencies.build(
                      **annotation_dependencies(build_context)
                    )
                    Shoko::Adapters::Input::Controllers::AnnotationOverlayController.new(deps: deps)
                  end

                  def build_in_book_search(build_context)
                    Shoko::Adapters::Input::Controllers::InBookSearchController.new(
                      **in_book_search_dependencies(build_context)
                    )
                  end

                  def annotation_dependencies(build_context)
                    runtime_context = build_context.runtime_context
                    {
                      reader_state: runtime_context.reader_state_reader,
                      reader_session_mutator: runtime_context.reader_session_mutator,
                      state_controller: build_context.state_controller,
                      input_controller: build_context.input_controller,
                      annotation_service: runtime_context.annotation_service,
                      dictionary_service: runtime_context.dictionary_service,
                      annotation_overlay_ui_session: runtime_context.annotation_overlay_ui_session,
                      notification_service: runtime_context.notification_service,
                      logger: runtime_context.logger,
                    }
                  end
                  private_class_method :annotation_dependencies

                  def in_book_search_dependencies(build_context)
                    runtime_context = build_context.runtime_context
                    {
                      reader_state: runtime_context.reader_state_reader,
                      reader_session_mutator: runtime_context.reader_session_mutator,
                      search_service: runtime_context.in_book_search_service,
                      input_controller: build_context.input_controller,
                      reader_controller: build_context.controller,
                      state_controller: build_context.state_controller,
                      in_book_search_ui_session: runtime_context.in_book_search_ui_session,
                      notification_service: runtime_context.notification_service,
                      logger: runtime_context.logger,
                      clock: runtime_context.clock,
                    }
                  end
                  private_class_method :in_book_search_dependencies
                end
              end
            end
          end
        end
      end
    end
  end
end
