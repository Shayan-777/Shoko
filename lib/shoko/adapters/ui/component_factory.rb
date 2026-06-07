# frozen_string_literal: true

require_relative 'components/main_menu_component'
require_relative 'menu_visual_profile'
require_relative 'theme_context'

module Shoko
  module Adapters
    module Ui
      # Factory for UI components used by input adapters/controllers.
      class ComponentFactory
        def initialize(config_reader: nil, color_mode: :dark, fallback_color_mode: nil)
          @config_reader = config_reader
          @fallback_color_mode = (fallback_color_mode || color_mode || :dark).to_sym
        end

        def annotations_overlay(state)
          require_relative 'components/annotations_overlay_component'

          Components::AnnotationsOverlayComponent.new(state)
        end

        def annotation_editor_overlay(reader_state_reader:, reader_session_mutator:, rendered_lines: nil)
          require_relative 'components/annotation_editor_overlay_component'

          context = current_theme_context
          Components::AnnotationEditorOverlayComponent.new(
            reader_state_reader: reader_state_reader,
            reader_session_mutator: reader_session_mutator,
            color_mode: context.color_mode,
            rendered_lines: rendered_lines
          )
        end

        # The dictionary setup/install wizard (centered). Lookup results render in
        # the bar-anchored definition card (see #dictionary_lookup_popup).
        def dictionary_popup(reader_state_reader = nil)
          require_relative 'components/dictionary_popup_component'

          context = current_theme_context
          Components::DictionaryPopupComponent.new(
            reader_state_reader: reader_state_reader,
            color_mode: context.color_mode
          )
        end

        def in_book_search_popup(reader_state_reader:, rendered_lines: nil)
          require_relative 'components/in_book_search_popup_component'

          context = current_theme_context
          Components::InBookSearchPopupComponent.new(
            reader_state_reader: reader_state_reader,
            color_mode: context.color_mode,
            rendered_lines: rendered_lines
          )
        end

        def dictionary_lookup_popup(reader_state_reader:)
          require_relative 'components/dictionary_lookup_popup_component'

          context = current_theme_context
          Components::DictionaryLookupPopupComponent.new(
            reader_state_reader: reader_state_reader,
            color_mode: context.color_mode
          )
        end

        def toc_lookup_popup(reader_state_reader:)
          require_relative 'components/toc_lookup_popup_component'

          context = current_theme_context
          Components::TocLookupPopupComponent.new(
            reader_state_reader: reader_state_reader,
            color_mode: context.color_mode
          )
        end

        def translator_lookup_popup(reader_state_reader:)
          require_relative 'components/translator_lookup_popup_component'

          context = current_theme_context
          Components::TranslatorLookupPopupComponent.new(
            reader_state_reader: reader_state_reader,
            color_mode: context.color_mode
          )
        end

        def enhanced_popup_menu(selection:, coordinate_service:, clipboard_service:, rendered:, dictionary_enabled:,
                                reader_state_reader: nil, reader_session_mutator: nil,
                                popup_position_service: nil, anchor_position: nil)
          require_relative 'components/enhanced_popup_menu'

          Components::EnhancedPopupMenu.new(
            selection,
            coordinate_service: coordinate_service,
            reader_state_reader: reader_state_reader,
            reader_session_mutator: reader_session_mutator,
            popup_position_service: popup_position_service,
            clipboard_service: clipboard_service,
            rendered_lines: rendered,
            dictionary_enabled: dictionary_enabled,
            anchor_position: anchor_position
          )
        end

        def annotation_editor_screen(controller:, annotation_service:, **)
          require_relative 'components/screens/annotation_editor_screen_component'

          Components::Screens::AnnotationEditorScreenComponent.new(
            controller,
            **,
            annotation_service: annotation_service
          )
        end

        def main_menu_component(controller:, menu_ui_dependencies:)
          context = current_theme_context
          menu_visual_profile = Shoko::Adapters::Ui::MenuVisualProfile.new(
            color_mode: context.color_mode,
            ascii_icons: ascii_icons_enabled?
          )
          Components::MainMenuComponent.new(
            controller,
            menu_ui_dependencies: menu_ui_dependencies,
            menu_visual_profile: menu_visual_profile
          )
        end

        def resolve_theme_context(theme_id: nil)
          Shoko::Adapters::Ui::ThemeContext.resolve(
            theme_id: theme_id || @config_reader&.theme,
            fallback_color_mode: @fallback_color_mode
          )
        end

        def apply_theme(theme_id: nil)
          Shoko::Adapters::Ui::ThemeContext.apply!(
            theme_id: theme_id || @config_reader&.theme,
            fallback_color_mode: @fallback_color_mode
          )
        end

        private

        def current_theme_context
          resolve_theme_context
        end

        def ascii_icons_enabled?
          value = ENV.fetch('SHOKO_ASCII_ICONS', '').to_s.strip.downcase
          %w[1 true yes on].include?(value)
        end
      end
    end
  end
end
