# frozen_string_literal: true

require_relative 'components/annotations_overlay_component'
require_relative 'components/annotation_editor_overlay_component'
require_relative 'components/dictionary_panel_component'
require_relative 'components/dictionary_popup_component'
require_relative 'components/in_book_search_popup_component'
require_relative 'components/enhanced_popup_menu'
require_relative 'components/main_menu_component'
require_relative 'components/screens/annotation_editor_screen_component'
require_relative 'menu_visual_profile'

module Shoko
  module Adapters
    module Ui
      # Factory for UI components used by input adapters/controllers.
      class ComponentFactory
        def initialize(color_mode: :dark)
          @color_mode = color_mode
          @menu_visual_profile = Shoko::Adapters::Ui::MenuVisualProfile.new(
            color_mode: color_mode,
            ascii_icons: ascii_icons_enabled?
          )
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

        def enhanced_popup_menu(selection:, coordinate_service:, popup_position_service: nil,
                                clipboard_service:, rendered:, dictionary_enabled:, anchor_position: nil)
          Components::EnhancedPopupMenu.new(
            selection,
            nil,
            coordinate_service,
            popup_position_service,
            clipboard_service,
            rendered,
            dictionary_enabled: dictionary_enabled,
            anchor_position: anchor_position
          )
        end

        def annotation_editor_screen(controller:, annotation_service:, **)
          Components::Screens::AnnotationEditorScreenComponent.new(
            controller,
            **,
            annotation_service: annotation_service
          )
        end

        def main_menu_component(controller:, menu_ui_dependencies:)
          Components::MainMenuComponent.new(
            controller,
            menu_ui_dependencies: menu_ui_dependencies,
            menu_visual_profile: @menu_visual_profile
          )
        end

        private

        def ascii_icons_enabled?
          value = ENV.fetch('SHOKO_ASCII_ICONS', '').to_s.strip.downcase
          %w[1 true yes on].include?(value)
        end
      end
    end
  end
end
