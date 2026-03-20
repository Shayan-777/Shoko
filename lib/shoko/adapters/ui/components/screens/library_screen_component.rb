# frozen_string_literal: true

require 'time'

require_relative 'base_screen_component'
require_relative '../../constants/ui_constants'
require_relative '../menu_design/master_detail_shell'
require_relative '../menu_design/table_renderer'
require_relative '../ui/list_helpers'
require_relative '../ui/text_utils'
require_relative '../../../../shared/terminal/text_sanitizer'
require_relative 'library_screen_component/detail_renderer'
require_relative 'library_screen_component/list_renderer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Library screen component that renders cached books with an optional
          # metadata inspector.
          class LibraryScreenComponent < BaseScreenComponent
            include Adapters::Ui::Constants::Ui
            include Ui::TextUtils
            include LibraryScreenComponentDetailRenderer
            include LibraryScreenComponentListRenderer

            Item = Struct.new(:title, :authors, :year, :last_accessed, :size_bytes, :open_path, :epub_path)

            TIME_INTERVALS = [
              { max: 3600, div: 60, singular: 'a minute ago', plural: '%d minutes ago' },
              { max: 86_400, div: 3600, singular: 'an hour ago', plural: '%d hours ago' },
              { max: 604_800, div: 86_400, singular: 'yesterday', plural: '%d days ago' },
              { max: Float::INFINITY, div: 604_800, singular: 'a week ago', plural: '%d weeks ago' },
            ].freeze
            DETAIL_KEY_WIDTH = 9

            def initialize(observer_registry, dependencies, menu_visual_profile: nil)
              super(dependencies)
              @observer_registry = observer_registry
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @catalog = dependencies&.catalog_service
              @items = nil
              @menu_state_reader = nil
              @observer_registry.add_observer(self, %i[menu browse_selected], %i[menu library_details_open])
            end

            def state_changed(_path, _old, _new)
              invalidate
            end

            def do_render(surface, bounds)
              context = render_context(surface, bounds)
              render_shell(context)
              render_primary_panel(surface, bounds, context)
              render_details_panel(surface, bounds, details_context(context))
            end

            private

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end

            def render_context(surface, bounds)
              items = load_items
              selected = selected_index(items.length)
              details_open = details_open?
              shell = MenuDesign::MasterDetailShell.new(surface, bounds)
              layout = shell.build_layout(
                detail_visible: details_open,
                desired_detail_width: 32,
                min_primary_width: 34,
                min_detail_width: 28,
                stacked_detail_height: 9
              )
              { shell: shell, layout: layout, items: items, selected: selected, details_open: details_open }
            end

            def render_shell(context)
              items = context[:items]
              details_open = context[:details_open]
              context[:shell].render_frame(
                layout: context[:layout],
                title: 'Library',
                hint: 'ENTER open  SPACE details  ESC back',
                summary_left: "#{items.length} cached #{items.length == 1 ? 'book' : 'books'}",
                summary_right: details_open ? 'Inspector visible' : 'SPACE shows metadata',
                footer: footer_text(items.length, details_open)
              )
              context[:shell].render_panels(
                layout: context[:layout],
                primary_title: 'Cached Books',
                secondary_title: 'Details'
              )
            end

            def render_primary_panel(surface, bounds, context)
              panel = context[:layout].primary_panel.content
              if context[:items].empty?
                render_empty(surface, bounds, panel)
              else
                render_library(surface, bounds, panel: panel, items: context[:items], selected: context[:selected])
              end
            end

            def details_context(context)
              {
                panel: context[:layout].secondary_panel&.content,
                item: context[:items][context[:selected]],
                selected: context[:selected],
                total: context[:items].length,
              }
            end

            def load_items
              return @items if @items

              entries = Array(@catalog.cached_library_entries)
              @items = entries.map { |entry| build_item(entry) }
            end

            def build_item(entry)
              open_path = fetch_entry(entry, :open_path)
              Item.new(
                title: fetch_entry(entry, :title),
                authors: fetch_entry(entry, :authors),
                year: fetch_entry(entry, :year),
                last_accessed: fetch_entry(entry, :last_accessed),
                size_bytes: fetch_entry(entry, :size_bytes) || @catalog.size_for(open_path),
                open_path: open_path,
                epub_path: fetch_entry(entry, :epub_path)
              )
            end

            def fetch_entry(entry, key)
              return entry[key] if entry.is_a?(Struct)
              return entry.to_h[key] if entry.is_a?(Data)

              normalized = entry.transform_keys do |entry_key|
                entry_key.is_a?(String) ? entry_key.to_sym : entry_key
              end
              normalized[key]
            end

            def selected_index(total)
              return 0 if total <= 0

              current = (menu_state_reader&.browse_selected || 0).to_i
              current.clamp(0, total - 1)
            end

            def details_open?
              reader = menu_state_reader
              reader&.library_details_open? == true
            end

            def footer_text(count, details_open)
              noun = count == 1 ? 'book' : 'books'
              details_open ? "#{count} cached #{noun} • inspector open" : "#{count} cached #{noun}"
            end

            def safe_text(text)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(text.to_s, preserve_newlines: false, preserve_tabs: false)
            end

            public

            def items
              load_items
            end

            def invalidate_cache!
              @items = nil
            end
          end
        end
      end
    end
  end
end
