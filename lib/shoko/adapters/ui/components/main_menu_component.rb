# frozen_string_literal: true

require_relative 'base_component'
require_relative 'layouts/vertical'
require_relative 'screens/menu_screen_component'
require_relative 'screens/browse_screen_component'
require_relative 'screens/library_screen_component'
require_relative 'screens/settings_screen_component'
require_relative 'screens/dictionary_settings_screen_component'
require_relative 'screens/download_books_screen_component'
require_relative 'screens/annotations_screen_component'
require_relative 'screens/annotation_edit_screen_component'
require_relative 'screens/annotation_detail_screen_component'

module Shoko
  module Adapters
    module Ui
      module Components
        # Root component for the main menu system
        class MainMenuComponent < BaseComponent
          SCREEN_FACTORY_BUILDERS = {
            menu: :build_menu_screen,
            browse: :build_browse_screen,
            library: :build_library_screen,
            settings: :build_settings_screen,
            dictionary: :build_dictionary_screen,
            download: :build_download_screen,
            annotations: :build_annotations_screen,
            annotation_editor: :build_annotation_editor_screen,
            annotation_detail: :build_annotation_detail_screen,
          }.freeze

          def initialize(main_menu, menu_ui_dependencies:, menu_visual_profile: nil)
            super()
            @main_menu = main_menu
            @observer_registry = main_menu.observer_registry
            @menu_ui_dependencies = menu_ui_dependencies
            @menu_visual_profile = menu_visual_profile
            @catalog = @main_menu.catalog

            setup_screen_factories

            # Initialize current screen
            @current_screen = fetch_screen(:menu)

            # Observe mode changes to switch active component
            @observer_registry.add_observer(self, %i[menu mode], %i[menu selected])
          end

          def state_changed(path, _old_value, new_value)
            return unless path == %i[menu mode]

            mapped = case new_value
                     when :search then :browse
                     when :dictionary_search then :dictionary
                     when :download_search, :download, :download_source_select then :download
                     else new_value
                     end
            @current_screen = fetch_screen(mapped) || fetch_screen(:menu)
          end

          def do_render(surface, bounds)
            current_screen&.render(surface, bounds)
          end

          def preferred_height(_available_height)
            :fill
          end

          attr_reader :current_screen

          # Delegate screen-specific methods
          def browse_screen
            fetch_screen(:browse)
          end

          def library_screen
            fetch_screen(:library)
          end

          # recent screen removed

          def settings_screen
            fetch_screen(:settings)
          end

          def download_books_screen
            fetch_screen(:download)
          end

          def annotations_screen
            fetch_screen(:annotations)
          end

          def annotation_detail_screen
            fetch_screen(:annotation_detail)
          end

          private

          def setup_screen_factories
            @screen_components = {}
            @screen_factories = SCREEN_FACTORY_BUILDERS.transform_values { |builder| -> { send(builder) } }
          end

          def build_menu_screen
            Screens::MenuScreenComponent.new(
              @observer_registry,
              @menu_ui_dependencies,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def build_browse_screen
            screen = Screens::BrowseScreenComponent.new(
              @catalog,
              @observer_registry,
              @menu_ui_dependencies,
              menu_visual_profile: @menu_visual_profile
            )
            screen.filtered_epubs = @catalog.entries || []
            screen
          end

          def build_library_screen
            Screens::LibraryScreenComponent.new(
              @observer_registry,
              @menu_ui_dependencies,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def build_settings_screen
            Screens::SettingsScreenComponent.new(
              @catalog,
              dependencies: @menu_ui_dependencies,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def build_dictionary_screen
            Screens::DictionarySettingsScreenComponent.new(
              dependencies: @menu_ui_dependencies,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def build_download_screen
            Screens::DownloadBooksScreenComponent.new(
              dependencies: @menu_ui_dependencies,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def build_annotations_screen
            Screens::AnnotationsScreenComponent.new(
              dependencies: @menu_ui_dependencies,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def build_annotation_editor_screen
            Screens::AnnotationEditScreenComponent.new(
              @menu_ui_dependencies,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def build_annotation_detail_screen
            Screens::AnnotationDetailScreenComponent.new(
              dependencies: @menu_ui_dependencies,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def fetch_screen(key)
            @screen_components[key] ||= @screen_factories[key]&.call
          end

          public

          def annotation_edit_screen
            fetch_screen(:annotation_editor)
          end
        end
      end
    end
  end
end
