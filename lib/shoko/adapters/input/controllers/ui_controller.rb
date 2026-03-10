# frozen_string_literal: true

require_relative 'ui_controller/mode_switching'
require_relative 'ui_controller/popup_actions'
require_relative 'ui_controller/delegation_facade'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Coordinates all UI-related functionality by delegating to specialized controllers.
        class UIController
          include UiControllerModeSwitching
          include UiControllerPopupActions
          include UiControllerDelegationFacade

          # Raised when required dependencies are missing for a UI action.
          class MissingDependencyError < StandardError; end

          Dependencies = Data.define(
            :reader_state,
            :config_reader,
            :reader_session_mutator,
            :sidebar_state,
            :ui_state,
            :sidebar_controller,
            :dictionary_controller,
            :annotation_controller,
            :in_book_search_controller,
            :input_controller,
            :reader_controller,
            :notification_service,
            :selection_service,
            :rendered_content_reader,
            :clipboard_service,
            :ui_component_factory,
            :annotation_service,
            :logger
          ) do
            REQUIRED_FIELDS = %i[
              reader_state
              config_reader
              reader_session_mutator
              sidebar_controller
              dictionary_controller
              annotation_controller
              in_book_search_controller
              input_controller
              notification_service
            ].freeze

            def validate!
              values = to_h
              missing = REQUIRED_FIELDS.select { |field| values[field].nil? }
              return self if missing.empty?

              raise ArgumentError, "Missing required UI controller dependencies: #{missing.join(', ')}"
            end
          end

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

            @reader_state = dependencies.reader_state
            @config_reader = dependencies.config_reader
            @reader_session_mutator = dependencies.reader_session_mutator
            @sidebar_state = dependencies.sidebar_state
            @ui_state = dependencies.ui_state

            @sidebar_controller = dependencies.sidebar_controller
            @dictionary_controller = dependencies.dictionary_controller
            @annotation_controller = dependencies.annotation_controller
            @in_book_search_controller = dependencies.in_book_search_controller

            @input_controller = dependencies.input_controller
            @reader_controller = dependencies.reader_controller
            @notification_service = dependencies.notification_service
            @selection_service = dependencies.selection_service
            @rendered_content_reader = dependencies.rendered_content_reader
            @clipboard_service = dependencies.clipboard_service
            @ui_component_factory = dependencies.ui_component_factory
            @annotation_service = dependencies.annotation_service
            @logger = dependencies.logger
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
          end
        end
      end
    end
  end
end
