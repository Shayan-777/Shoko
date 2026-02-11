# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for creating UI components used by application controllers.
      # Keeps application logic decoupled from concrete adapter component classes.
      module UIComponentFactory
        # Build annotations overlay component.
        def annotations_overlay(state)
          raise NotImplementedError, "#{self.class} must implement #annotations_overlay"
        end

        # Build annotation editor overlay component.
        def annotation_editor_overlay(selected_text:, range:, chapter_index:, annotation: nil)
          raise NotImplementedError, "#{self.class} must implement #annotation_editor_overlay"
        end

        # Build dictionary panel component.
        def dictionary_panel(state)
          raise NotImplementedError, "#{self.class} must implement #dictionary_panel"
        end

        # Build dictionary popup component.
        def dictionary_popup
          raise NotImplementedError, "#{self.class} must implement #dictionary_popup"
        end

        # Build in-book search popup component.
        def in_book_search_popup
          raise NotImplementedError, "#{self.class} must implement #in_book_search_popup"
        end

        # Predicate for dictionary panel component.
        def dictionary_panel_component?(_component)
          raise NotImplementedError, "#{self.class} must implement #dictionary_panel_component?"
        end

        # Minimum terminal width for dictionary panel display.
        def dictionary_panel_min_terminal_width
          raise NotImplementedError, "#{self.class} must implement #dictionary_panel_min_terminal_width"
        end

        # Minimum content width for dictionary panel display.
        def dictionary_panel_min_width
          raise NotImplementedError, "#{self.class} must implement #dictionary_panel_min_width"
        end

        # Build enhanced popup menu component.
        def enhanced_popup_menu(selection:, coordinate_service:, clipboard_service:, rendered:, dictionary_enabled:)
          raise NotImplementedError, "#{self.class} must implement #enhanced_popup_menu"
        end

        # Build annotation editor screen component.
        def annotation_editor_screen(controller:, annotation_service:, **kwargs)
          raise NotImplementedError, "#{self.class} must implement #annotation_editor_screen"
        end

        # Build main menu component.
        def main_menu_component(controller:, menu_ui_dependencies:)
          raise NotImplementedError, "#{self.class} must implement #main_menu_component"
        end
      end
    end
  end
end
