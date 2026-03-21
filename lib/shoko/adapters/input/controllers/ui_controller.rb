# frozen_string_literal: true

require_relative 'dependencies/ui_controller_dependencies'
require_relative 'ui_controller/mode_switching'
require_relative 'ui_controller/popup_actions'
require_relative 'ui_controller/translation_popup'
require_relative 'ui_controller/delegation_facade'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Coordinates all UI-related functionality by delegating to specialized controllers.
        class UIController
          include UiControllerModeSwitching
          include UiControllerPopupActions
          include UiControllerTranslationPopup
          include UiControllerDelegationFacade

          # Raised when required dependencies are missing for a UI action.
          class MissingDependencyError < StandardError; end

          Dependencies = Shoko::Adapters::Input::Controllers::Dependencies::UiControllerDependencies::Bundle

          # Builds the annotation editor screen component for annotation editor mode.
          class AnnotationEditorMode
            def initialize(controller, annotation_service, component_factory)
              @controller = controller
              @annotation_service = annotation_service
              @component_factory = component_factory
            end

            def build_component(**)
              @component_factory.annotation_editor_screen(
                controller: @controller,
                annotation_service: @annotation_service,
                **
              )
            end
          end

          attr_reader :current_mode

          def initialize(deps:)
            dependencies = deps.validate!
            assign_state_dependencies(dependencies.state)
            assign_controller_dependencies(dependencies.controllers)
            assign_service_dependencies(dependencies.services)
            @current_mode = nil
          end

          def refresh_theme(theme_context: nil, theme: nil)
            context = resolve_theme_context(theme_context: theme_context, theme: theme)
            propagate_theme_context(context)
            context
          # resilient-boundary
          rescue Shoko::Error => e
            @logger&.debug('ui_controller.refresh_theme_failed', error: e.class.name, message: e.message)
            nil
          end

          private

          def resolve_theme_context(theme_context:, theme:)
            return theme_context if theme_context

            @ui_component_factory&.apply_theme(theme_id: theme || @config_reader&.theme)
          end

          def propagate_theme_context(context)
            @dictionary_controller&.refresh_theme(theme_context: context)
            @annotation_controller&.refresh_theme(theme_context: context)
            @in_book_search_controller&.refresh_theme(theme_context: context)
            refresh_translation_popup_theme(theme_context: context)
          end

          def assign_state_dependencies(deps)
            @reader_state = deps.reader_state
            @config_reader = deps.config_reader
            @reader_session_mutator = deps.reader_session_mutator
            @sidebar_state = deps.sidebar_state
            @ui_state = deps.ui_state
            @selection_service = deps.selection_service
            @rendered_content_reader = deps.rendered_content_reader
          end

          def assign_controller_dependencies(deps)
            @sidebar_controller = deps.sidebar_controller
            @dictionary_controller = deps.dictionary_controller
            @annotation_controller = deps.annotation_controller
            @in_book_search_controller = deps.in_book_search_controller
            @input_controller = deps.input_controller
            @reader_controller = deps.reader_controller
          end

          def assign_service_dependencies(deps)
            @notification_service = deps.notification_service
            @clipboard_service = deps.clipboard_service
            @ui_component_factory = deps.ui_component_factory
            @annotation_service = deps.annotation_service
            @translation_service = deps.translation_service
            @logger = deps.logger
          end
        end
      end
    end
  end
end
