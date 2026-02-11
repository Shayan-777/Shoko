# frozen_string_literal: true

require_relative '../../../core/ports/ui_component_factory'
require_relative 'components/annotations_overlay_component'
require_relative 'components/annotation_editor_overlay_component'
require_relative 'components/dictionary_panel_component'
require_relative 'components/dictionary_popup_component'
require_relative 'components/in_book_search_popup_component'
require_relative 'components/enhanced_popup_menu'
require_relative 'components/main_menu_component'
require_relative 'components/screens/annotation_editor_screen_component'

module Shoko
  module Adapters
    module Output
      module Ui
        # Factory for UI components used by application controllers.
        class ComponentFactory
          include Core::Ports::UIComponentFactory

          def initialize(color_mode: :dark)
            @color_mode = color_mode
          end

          def annotations_overlay(state)
            Components::AnnotationsOverlayComponent.new(state)
          end

          def annotation_editor_overlay(selected_text:, range:, chapter_index:, annotation: nil)
            Components::AnnotationEditorOverlayComponent.new(
              selected_text: selected_text,
              range: range,
              chapter_index: chapter_index,
              annotation: annotation,
              color_mode: @color_mode
            )
          end

          def dictionary_panel(state)
            Components::DictionaryPanelComponent.new(state)
          end

          def dictionary_popup
            Components::DictionaryPopupComponent.new(color_mode: @color_mode)
          end

          def in_book_search_popup
            Components::InBookSearchPopupComponent.new(color_mode: @color_mode)
          end

          def dictionary_panel_component?(component)
            component.is_a?(Components::DictionaryPanelComponent)
          end

          def dictionary_panel_min_terminal_width
            Components::DictionaryPanelComponent::MIN_TERMINAL_WIDTH
          end

          def dictionary_panel_min_width
            Components::DictionaryPanelComponent::MIN_WIDTH
          end

          def enhanced_popup_menu(selection:, coordinate_service:, clipboard_service:, rendered:, dictionary_enabled:)
            Components::EnhancedPopupMenu.new(
              selection,
              nil,
              coordinate_service,
              clipboard_service,
              rendered,
              dictionary_enabled: dictionary_enabled
            )
          end

          def annotation_editor_screen(controller:, dependencies:, **)
            Components::Screens::AnnotationEditorScreenComponent.new(
              controller,
              **,
              dependencies: dependencies
            )
          end

          def main_menu_component(controller, dependencies:)
            Components::MainMenuComponent.new(controller, dependencies)
          end
        end
      end
    end
  end
end
