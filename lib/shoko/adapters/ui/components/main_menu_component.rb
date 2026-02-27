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

module Shoko
  module Adapters
    module Ui
      module Components
        # Root component for the main menu system
        class MainMenuComponent < BaseComponent
          def initialize(main_menu, menu_ui_dependencies:)
            super()
            @main_menu = main_menu
            @observer_registry = main_menu.observer_registry
            @menu_ui_dependencies = menu_ui_dependencies
            @catalog = @main_menu.catalog

            setup_screen_components

            # Initialize current screen
            @current_screen = @screen_components[:menu]

            # Observe mode changes to switch active component
            @observer_registry.add_observer(self, %i[menu mode], %i[menu selected])
          end

          def state_changed(path, _old_value, new_value)
            return unless path == %i[menu mode]

            mapped = case new_value
                     when :search then :browse
                     when :dictionary_search then :dictionary
                     when :download_search, :download then :download
                     else new_value
                     end
            @current_screen = @screen_components[mapped] || @screen_components[:menu]
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
            @screen_components[:browse]
          end

          def library_screen
            @screen_components[:library]
          end

          # recent screen removed

          def settings_screen
            @screen_components[:settings]
          end

          def download_books_screen
            @screen_components[:download]
          end

          def annotations_screen
            @screen_components[:annotations]
          end

          def annotation_detail_screen
            @screen_components[:annotation_detail]
          end

          private

          def setup_screen_components
            @screen_components = {
              menu: Screens::MenuScreenComponent.new(@observer_registry, @menu_ui_dependencies),
              browse: Screens::BrowseScreenComponent.new(@catalog, @observer_registry, @menu_ui_dependencies),
              library: Screens::LibraryScreenComponent.new(@observer_registry, @menu_ui_dependencies),
              settings: Screens::SettingsScreenComponent.new(@catalog, dependencies: @menu_ui_dependencies),
              dictionary: Screens::DictionarySettingsScreenComponent.new(dependencies: @menu_ui_dependencies),
              download: Screens::DownloadBooksScreenComponent.new(dependencies: @menu_ui_dependencies),
              annotations: Screens::AnnotationsScreenComponent.new(dependencies: @menu_ui_dependencies),
              annotation_editor: Screens::AnnotationEditScreenComponent.new(@menu_ui_dependencies),
              annotation_detail: Screens::AnnotationDetailScreenComponent.new(dependencies: @menu_ui_dependencies),
            }
          end

          public

          def annotation_edit_screen
            @screen_components[:annotation_editor]
          end
        end
      end
    end
  end
end
