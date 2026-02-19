# frozen_string_literal: true

require_relative 'sidebar_controller'
require_relative 'dictionary_controller'
require_relative 'annotation_overlay_controller'
require_relative 'in_book_search_controller'
require_relative 'ui_controller/mode_switching'
require_relative 'ui_controller/popup_actions'
require_relative 'ui_controller/delegation_facade'

module Shoko
  module Application
    module Controllers
      # Coordinates all UI-related functionality by delegating to specialized controllers.
      class UIController
        include UiControllerModeSwitching
        include UiControllerPopupActions
        include UiControllerDelegationFacade

        # Raised when required dependencies are missing for a UI action.
        class MissingDependencyError < StandardError; end

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

        def initialize(reader_state:, config_reader:, state_writer:, sidebar_state:, ui_state:,
                       notification_service: nil, selection_service: nil,
                       rendered_content_reader: nil, clipboard_service: nil,
                       ui_component_factory: nil, input_controller: nil,
                       reader_controller: nil, state_controller: nil,
                       annotation_service: nil, dictionary_service: nil,
                       dictionary_catalog_service: nil,
                       terminal_service: nil, layout_metrics: nil, layout_service: nil,
                       document: nil, navigation_service: nil, bookmark_service: nil,
                       dictionary_ui_session: nil, in_book_search_ui_session: nil,
                       annotation_overlay_ui_session: nil,
                       in_book_search_service: nil,
                       render_registry: nil, settings_service: nil, logger: nil,
                       dictionary_availability: nil, dictionary_storage: nil,
                       runtime_config: nil, formatting_service: nil, clock: nil)
          @reader_state = reader_state
          @config_reader = config_reader
          @state_writer = state_writer
          @sidebar_state = sidebar_state
          @ui_state = ui_state
          @dependencies_hash = {
            notification_service: notification_service,
            selection_service: selection_service,
            rendered_content_reader: rendered_content_reader,
            clipboard_service: clipboard_service,
            ui_component_factory: ui_component_factory,
            input_controller: input_controller,
            reader_controller: reader_controller,
            state_controller: state_controller,
            annotation_service: annotation_service,
            render_registry: render_registry,
            logger: logger,
            runtime_config: runtime_config,
          }
          @notification_service = notification_service
          @selection_service = selection_service
          @rendered_content_reader = rendered_content_reader
          @clipboard_service = clipboard_service
          @ui_component_factory = ui_component_factory
          @input_controller = input_controller
          @reader_controller = reader_controller
          @state_controller = state_controller
          @annotation_service = annotation_service
          @in_book_search_service = in_book_search_service
          @dictionary_ui_session = dictionary_ui_session
          @in_book_search_ui_session = in_book_search_ui_session
          @annotation_overlay_ui_session = annotation_overlay_ui_session
          @logger = logger
          @current_mode = nil

          @sidebar_controller = SidebarController.new(
            reader_state: reader_state,
            config_reader: config_reader,
            state_writer: state_writer,
            sidebar_state: sidebar_state,
            ui_state: ui_state,
            document: document,
            navigation_service: navigation_service,
            bookmark_service: bookmark_service,
            state_controller: state_controller,
            ui_controller: self,
            notification_service: notification_service,
            formatting_service: formatting_service,
            layout_service: layout_service
          )
          @dictionary_controller = DictionaryController.new(
            reader_state: reader_state,
            config_reader: config_reader,
            sidebar_state: sidebar_state,
            state_writer: state_writer,
            layout_metrics: layout_metrics,
            dictionary_service: dictionary_service,
            dictionary_catalog_service: dictionary_catalog_service,
            terminal_service: terminal_service,
            ui_component_factory: ui_component_factory,
            logger: logger,
            input_controller: input_controller,
            layout_service: layout_service,
            reader_controller: reader_controller,
            document: document,
            selection_service: selection_service,
            rendered_content_reader: rendered_content_reader,
            notification_service: notification_service,
            settings_service: settings_service,
            dictionary_availability: dictionary_availability,
            dictionary_storage: dictionary_storage,
            dictionary_ui_session: dictionary_ui_session,
            ui_controller: self,
            clock: clock
          )
          @annotation_controller = AnnotationOverlayController.new(
            reader_state: reader_state,
            state_writer: state_writer,
            ui_component_factory: ui_component_factory,
            state_controller: state_controller,
            reader_controller: reader_controller,
            input_controller: input_controller,
            annotation_service: annotation_service,
            annotation_overlay_ui_session: annotation_overlay_ui_session,
            notification_service: notification_service,
            logger: logger
          )
          @in_book_search_controller = InBookSearchController.new(
            reader_state: reader_state,
            state_writer: state_writer,
            search_service: @in_book_search_service,
            input_controller: input_controller,
            reader_controller: reader_controller,
            state_controller: state_controller,
            in_book_search_ui_session: in_book_search_ui_session,
            notification_service: notification_service,
            logger: logger
          )
        end

        attr_reader :current_mode

        # Setter injection for circular dependency resolution.
        def input_controller=(controller)
          @input_controller = controller
          @dependencies_hash[:input_controller] = controller
          @dictionary_controller.input_controller = controller
          @annotation_controller.input_controller = controller
          @in_book_search_controller.input_controller = controller
        end

        def state_controller=(controller)
          @state_controller = controller
          @dependencies_hash[:state_controller] = controller
          @annotation_controller.state_controller = controller
          @sidebar_controller.state_controller = controller
          @in_book_search_controller.state_controller = controller
        end
      end
    end
  end
end
