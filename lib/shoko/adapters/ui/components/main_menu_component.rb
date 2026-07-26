# frozen_string_literal: true

require_relative 'base_component'
require_relative 'rect'
require_relative 'layouts/vertical'
require_relative 'status_bar_component'
require_relative 'status_bar/menu_status_context_builder'
require_relative 'menu_design/rail'
require_relative 'screens/landing/layout'
require_relative 'screens/menu_screen_component'
require 'shoko/application/ports/inbound/menu_catalog'
require_relative 'screens/browse_screen_component'
require_relative 'screens/library_screen_component'
require_relative 'screens/settings_screen_component'
require_relative 'screens/dictionary_settings_screen_component'
require_relative 'screens/translator_packs_screen_component'
require_relative 'screens/download_books_screen_component'
require_relative 'screens/translator_screen_component'
require_relative 'screens/rss_reader_screen_component'
require_relative 'screens/rss_lookup_screen_component'
require_relative 'screens/annotations_screen_component'
require_relative 'screens/annotation_edit_screen_component'
require_relative 'screens/annotation_detail_screen_component'

module Shoko
  module Adapters
    module Ui
      module Components
        # Root component for the main menu system: the app shell. When the
        # terminal is wide enough it keeps the slate rail visible in every
        # menu view — the landing screen and each opened view render on the
        # elevated canvas beside it, so the whole menu reads as one
        # master-detail application. The rail marks the active view with the
        # family's selection strip; compartments separate purely by their
        # background elevation.
        class MainMenuComponent < BaseComponent
          MENU_ITEMS = Shoko::Application::Ports::Inbound::MenuCatalog.main_menu_items

          # Menu modes -> the rail entry they belong to.
          MODE_TO_RAIL_KEY = {
            menu: nil,
            browse: :browse, search: :browse,
            library: :library,
            annotations: :annotations, annotation_detail: :annotations, annotation_editor: :annotations,
            rss_reader: :rss_reader, rss_reader_feed_input: :rss_reader, rss_reader_filter: :rss_reader,
            rss_reader_find: :rss_reader, rss_reader_lookup: :rss_reader,
            download: :download, download_search: :download, download_source_select: :download,
            translator: :translator, translator_source_dropdown: :translator, translator_target_dropdown: :translator,
            settings: :settings, dictionary: :settings, dictionary_search: :settings,
            translator_packs: :settings, translator_packs_search: :settings
          }.freeze

          SCREEN_FACTORY_BUILDERS = {
            menu: :build_menu_screen,
            browse: :build_browse_screen,
            library: :build_library_screen,
            settings: :build_settings_screen,
            dictionary: :build_dictionary_screen,
            translator_packs: :build_translator_packs_screen,
            download: :build_download_screen,
            translator: :build_translator_screen,
            rss_reader: :build_rss_reader_screen,
            rss_lookup: :build_rss_lookup_screen,
            annotations: :build_annotations_screen,
            annotation_editor: :build_annotation_editor_screen,
            annotation_detail: :build_annotation_detail_screen,
          }.freeze

          def initialize(main_menu, menu_ui_dependencies:, menu_visual_profile: nil)
            super()
            @main_menu = main_menu
            @menu_ui_dependencies = menu_ui_dependencies
            @menu_visual_profile = menu_visual_profile
            @observer_registry = menu_ui_dependencies.observer_registry
            @catalog = menu_ui_dependencies.catalog_service

            setup_screen_factories

            # Initialize current screen
            @current_screen = fetch_screen(:menu)
            @status_bar = build_status_bar

            # Observe mode changes to switch active component
            @observer_registry.add_observer(self, %i[menu mode])
          end

          # Sub-modes (a search bar, a dropdown, the find bar) keep their
          # parent screen on screen; the table says which screen owns each.
          SCREEN_FOR_MODE = {
            search: :browse,
            dictionary_search: :dictionary,
            translator_packs_search: :translator_packs,
            download_search: :download, download: :download, download_source_select: :download,
            translator_source_dropdown: :translator, translator_target_dropdown: :translator,
            rss_reader_feed_input: :rss_reader, rss_reader_filter: :rss_reader,
            rss_reader_find: :rss_reader, rss_reader_lookup: :rss_lookup
          }.freeze

          def state_changed(_path, _old_value, new_value)
            mapped = SCREEN_FOR_MODE.fetch(new_value, new_value)
            @current_screen = fetch_screen(mapped) || fetch_screen(:menu)
          end

          def do_render(surface, bounds)
            bar_height = @status_bar ? @status_bar.preferred_height(bounds.height) : 0
            content_height = [bounds.height - bar_height, 0].max
            content = screen_bounds(bounds, content_height)

            hit_registry&.begin_frame!
            canvas = render_rail_shell(surface, content)
            @canvas_bounds = canvas
            sync_landing_layout(rail_visible: !canvas.equal?(content))
            current_screen&.render(surface, canvas)
            render_status_bar(surface, bounds, content_height, bar_height)
          end

          # The rect the active view rendered into on the last frame — mouse
          # routing translates terminal coordinates into it.
          attr_reader :canvas_bounds

          def preferred_height(_available_height)
            :fill
          end

          def hit_registry
            @menu_ui_dependencies&.menu_hit_registry
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

          def translator_screen
            fetch_screen(:translator)
          end

          def rss_reader_screen
            fetch_screen(:rss_reader)
          end

          def annotations_screen
            fetch_screen(:annotations)
          end

          def annotation_detail_screen
            fetch_screen(:annotation_detail)
          end

          private

          def screen_bounds(bounds, content_height)
            Rect.new(x: bounds.x, y: bounds.y, width: bounds.width, height: content_height)
          end

          # Renders the persistent rail and returns the canvas the active view
          # renders into; on narrow terminals the rail steps aside and views
          # take the whole content area.
          def render_rail_shell(surface, content)
            return content unless Screens::Landing::Layout.wide?(content)

            metrics = Screens::Landing::Layout.metrics(
              content,
              content_width: MenuDesign::Rail.content_width(MENU_ITEMS)
            )
            rail = MenuDesign::Rail.new(
              surface, content,
              width: metrics.rail_width, items: MENU_ITEMS, hits: hit_registry
            )
            rail.render(selected: rail_selected_index)
            canvas_rect(content, metrics)
          end

          def canvas_rect(content, metrics)
            Rect.new(
              x: content.x + metrics.rail_width,
              y: content.y,
              width: [content.width - metrics.rail_width, 0].max,
              height: content.height
            )
          end

          # On the landing screen the rail cursor follows the stored selection;
          # inside a view it pins to the entry that opened the view.
          def rail_selected_index
            reader = @menu_ui_dependencies&.menu_state_reader
            mode = (reader&.mode || :menu).to_sym
            key = MODE_TO_RAIL_KEY.fetch(mode, nil)
            return MENU_ITEMS.index { |item| item.key == key } || 0 if key

            (reader&.selected || 0).to_i.clamp(0, MENU_ITEMS.length - 1)
          end

          # The landing screen renders its preview canvas beside the rail and
          # its compact centered list when the rail is hidden; the shell owns
          # that decision, so pass it down each frame.
          def sync_landing_layout(rail_visible:)
            screen = current_screen
            screen.canvas_mode = rail_visible if screen.respond_to?(:canvas_mode=)
          end

          def render_status_bar(surface, bounds, content_height, bar_height)
            return unless bar_height.positive?

            bar_bounds = Rect.new(
              x: bounds.x,
              y: bounds.y + content_height,
              width: bounds.width,
              height: bar_height
            )
            @status_bar.render(surface, bar_bounds)
          end

          def build_status_bar
            menu_state_reader = @menu_ui_dependencies&.menu_state_reader
            context_builder = StatusBar::MenuStatusContextBuilder.new(
              menu_state_reader: menu_state_reader,
              library_count: -> { Array(@catalog&.entries).size },
              browse_selection: -> { browse_selection_snapshot(menu_state_reader) }
            )
            StatusBarComponent.new(context_builder)
          end

          def browse_selection_snapshot(menu_state_reader)
            screen = fetch_screen(:browse)
            {
              book: screen&.selected_book,
              index: menu_state_reader ? menu_state_reader.browse_selected.to_i : 0,
              total: screen ? screen.filtered_count.to_i : 0,
            }
          end

          # Screens receive exactly the collaborators they use — the bag
          # stops at this component; no screen carries a locator surface.
          def deps
            @menu_ui_dependencies
          end

          def setup_screen_factories
            @screen_components = {}
            @screen_factories = SCREEN_FACTORY_BUILDERS.transform_values { |builder| -> { send(builder) } }
          end

          def build_menu_screen
            Screens::MenuScreenComponent.new(
              menu_state_reader: deps.menu_state_reader,
              menu_hit_registry: deps.menu_hit_registry,
              menu_visual_profile: @menu_visual_profile,
              preview_screen_provider: ->(key) { preview_screen_for(key) }
            )
          end

          # The landing preview renders the real destination view for the
          # highlighted rail entry, so the canvas shows the true site rather
          # than a stand-in. It reuses the very screen instances the shell
          # opens, so a preview and its opened view are always identical. Quit
          # has no view; the landing screen renders its farewell instead.
          def preview_screen_for(key)
            return nil if key == :quit

            fetch_screen(key)
          end

          def build_browse_screen
            screen = Screens::BrowseScreenComponent.new(
              @catalog,
              @observer_registry,
              menu_state_reader: deps.menu_state_reader,
              menu_session_mutator: deps.menu_session_mutator,
              menu_hit_registry: deps.menu_hit_registry,
              menu_visual_profile: @menu_visual_profile
            )
            screen.filtered_epubs = @catalog.entries || []
            screen
          end

          def build_library_screen
            Screens::LibraryScreenComponent.new(
              menu_state_reader: deps.menu_state_reader,
              catalog_service: deps.catalog_service,
              menu_hit_registry: deps.menu_hit_registry,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def build_settings_screen
            Screens::SettingsScreenComponent.new(
              @catalog,
              menu_state_reader: deps.menu_state_reader,
              config_reader: deps.config_reader,
              menu_hit_registry: deps.menu_hit_registry,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def build_dictionary_screen
            Screens::DictionarySettingsScreenComponent.new(
              menu_state_reader: deps.menu_state_reader,
              config_reader: deps.config_reader,
              runtime_config: deps.runtime_config,
              dictionary_availability: deps.dictionary_availability,
              dictionary_storage: deps.dictionary_storage,
              menu_hit_registry: deps.menu_hit_registry,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def build_translator_packs_screen
            Screens::TranslatorPacksScreenComponent.new(
              menu_state_reader: deps.menu_state_reader,
              config_reader: deps.config_reader,
              menu_hit_registry: deps.menu_hit_registry,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def build_download_screen
            Screens::DownloadBooksScreenComponent.new(
              menu_state_reader: deps.menu_state_reader,
              config_reader: deps.config_reader,
              menu_hit_registry: deps.menu_hit_registry,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def build_translator_screen
            Screens::TranslatorScreenComponent.new(
              menu_state_reader: deps.menu_state_reader,
              menu_session_mutator: deps.menu_session_mutator,
              menu_hit_registry: deps.menu_hit_registry,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def build_rss_lookup_screen
            Screens::RssLookupScreenComponent.new(menu_state_reader: deps.menu_state_reader)
          end

          def build_rss_reader_screen
            Screens::RssReaderScreenComponent.new(
              menu_state_reader: deps.menu_state_reader,
              menu_hit_registry: deps.menu_hit_registry,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def build_annotations_screen
            Screens::AnnotationsScreenComponent.new(
              menu_state_reader: deps.menu_state_reader,
              reader_state_reader: deps.reader_state_reader,
              menu_hit_registry: deps.menu_hit_registry,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def build_annotation_editor_screen
            Screens::AnnotationEditScreenComponent.new(
              menu_state_reader: deps.menu_state_reader,
              menu_session_mutator: deps.menu_session_mutator,
              annotation_service: deps.annotation_service,
              menu_visual_profile: @menu_visual_profile
            )
          end

          def build_annotation_detail_screen
            Screens::AnnotationDetailScreenComponent.new(
              menu_state_reader: deps.menu_state_reader,
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
