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
  module Adapters::Output::Ui::Components
    # Root component for the main menu system
    class MainMenuComponent < BaseComponent
      def initialize(main_menu, dependencies)
        super()
        @main_menu = main_menu
        @state = main_menu.state
        @dependencies = dependencies
        @catalog = @main_menu.catalog

        setup_screen_components

        # Initialize current screen
        @current_screen = @screen_components[:menu]

        # Observe mode changes to switch active component
        @state.add_observer(self, %i[menu mode], %i[menu selected])
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
          menu: Screens::MenuScreenComponent.new(@state, @dependencies),
          browse: Screens::BrowseScreenComponent.new(@catalog, @state, @dependencies),
          library: Screens::LibraryScreenComponent.new(@state, @dependencies),
          settings: Screens::SettingsScreenComponent.new(@state, @catalog, dependencies: @dependencies),
          dictionary: Screens::DictionarySettingsScreenComponent.new(@state, dependencies: @dependencies),
          download: Screens::DownloadBooksScreenComponent.new(@state, dependencies: @dependencies),
          annotations: Screens::AnnotationsScreenComponent.new(@state, dependencies: @dependencies),
          annotation_editor: Screens::AnnotationEditScreenComponent.new(@state, @dependencies),
          annotation_detail: Screens::AnnotationDetailScreenComponent.new(@state, dependencies: @dependencies),
        }
      end

      public

      def annotation_edit_screen
        @screen_components[:annotation_editor]
      end
    end
  end
end
