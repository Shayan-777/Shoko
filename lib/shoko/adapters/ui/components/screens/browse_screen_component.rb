# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../../shared/terminal/text_sanitizer'
require_relative 'browse_screen_component/detail_renderer'
require_relative 'browse_screen_component/list_renderer'
require_relative '../menu_design/master_detail_shell'
require_relative '../menu_design/progress_renderer'
require_relative '../menu_design/search_field_renderer'
require_relative '../menu_design/table_renderer'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Browse screen component that renders the searchable library list
          # with a persistent inspector for the selected item.
          class BrowseScreenComponent < BaseComponent
            include Adapters::Ui::Constants::Ui
            include BrowseScreenComponentDetailRenderer
            include BrowseScreenComponentListRenderer
            include Ui::TextUtils

            DETAIL_KEY_WIDTH = 7
            BROWSE_PREFERRED_WIDTH = 132
            UNREADABLE_METADATA = Object.new.freeze

            def initialize(catalog_service, observer_registry, dependencies = nil, menu_visual_profile: nil)
              super()
              @catalog = catalog_service
              @observer_registry = observer_registry
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @filtered_epubs = []
              @menu_state_reader = nil
              @menu_session_mutator = nil

              @observer_registry.add_observer(self,
                                              %i[menu browse_selected],
                                              %i[menu search_query],
                                              %i[menu search_active])
            end

            def state_changed(path, _old_value, _new_value)
              filter_books if path == %i[menu search_query]
            end

            def filtered_epubs=(books)
              @filtered_epubs = apply_search_filter(books || [], menu_state_reader&.search_query)
            end

            def selected
              menu_state_reader&.browse_selected
            end

            def navigate(key)
              return unless @filtered_epubs.any?

              current = selected_index(@filtered_epubs.length)
              max_index = @filtered_epubs.length - 1
              new_selected = case key
                             when :up then [current - 1, 0].max
                             when :down then [current + 1, max_index].min
                             else current
                             end
              menu_session_mutator&.update_menu(browse_selected: new_selected)
            end

            def selected_book
              @filtered_epubs[selected_index(@filtered_epubs.length)]
            end

            def filtered_count
              @filtered_epubs.length
            end

            def book_at(index)
              @filtered_epubs[index]
            end

            def do_render(surface, bounds)
              @filtered_epubs ||= []
              shell = MenuDesign::MasterDetailShell.new(surface, bounds)
              layout = build_shell_layout(shell)
              summary = summary_context

              render_shell_frame(shell, layout, summary)
              render_search(surface, bounds, layout)
              shell.render_panels(layout: layout, primary_title: 'Results', secondary_title: 'Selection')

              if @filtered_epubs.empty?
                render_empty_results(surface, bounds, layout.primary_panel.content)
              else
                render_books_list(surface, bounds, layout.primary_panel.content)
              end

              render_selection_details(surface, bounds, layout.secondary_panel&.content)
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def build_shell_layout(shell)
              shell.build_layout(
                prelude_rows: 1,
                detail_visible: true,
                desired_detail_width: 40,
                min_primary_width: 38,
                min_detail_width: 30,
                stacked_detail_height: 8,
                preferred_width: BROWSE_PREFERRED_WIDTH
              )
            end

            def summary_context
              count_text, status_text, status_color = summary_payload
              { count_text: count_text, status_text: status_text, status_color: status_color }
            end

            def render_shell_frame(shell, layout, summary)
              shell.render_frame(
                layout: layout,
                title: 'Browse Library',
                hint: 'ENTER open  / search  ESC back',
                summary_left: summary[:count_text],
                summary_right: summary[:status_text],
                footer: footer_text,
                summary_right_color: summary[:status_color]
              )
            end

            def filter_books
              @filtered_epubs = apply_search_filter(@catalog.entries || [], menu_state_reader&.search_query)
            end

            def apply_search_filter(books, query)
              q = query.to_s.strip.downcase
              return books if q.empty?

              books.select do |book|
                name = book['name']&.downcase
                author = book['author']&.downcase
                name&.include?(q) || author&.include?(q)
              end
            end

            def summary_payload
              total = @filtered_epubs.length
              count_text = "Found #{total} #{total == 1 ? 'book' : 'books'}"
              status = @catalog.scan_status
              message = sanitize_text(@catalog.scan_message)
              case status
              when :scanning
                [count_text, message.empty? ? 'Scanning library' : "Scanning: #{message}", COLOR_TEXT_WARNING]
              when :error
                [count_text, message.empty? ? 'Scan failed' : message, COLOR_TEXT_ERROR]
              when :done
                [count_text, message.empty? ? 'Library ready' : message, COLOR_TEXT_DIM]
              else
                [count_text, '', COLOR_TEXT_DIM]
              end
            end

            def render_search(surface, bounds, layout)
              MenuDesign::SearchFieldRenderer.new(surface, bounds).render(
                label: 'Search',
                query: menu_state_reader&.search_query || '',
                cursor: menu_state_reader&.search_cursor,
                row: layout.prelude_top,
                indent: layout.shell_indent,
                width: layout.shell_width,
                active: menu_state_reader&.search_active? == true,
                compact: true
              )
            end

            def render_empty_results(surface, bounds, panel)
              status = @catalog.scan_status
              message = status == :scanning ? 'Scanning for books...' : 'No matching books'
              row = panel.y + [panel.height / 2, 0].max
              surface.write(bounds, row, panel.x, "#{COLOR_TEXT_DIM}#{message}#{Shoko::Shared::Terminal::Ansi::RESET}")
            end

            def display_author(meta, book)
              normalize_author(meta_value(meta, :author) || meta_value(meta, :authors) || book['author'])
            end

            def safe_metadata_for(book)
              @catalog.display_metadata_for(
                book['path'],
                size: book['size'],
                modified: book['modified']
              )
            rescue Shoko::MalformedMetadataInputError
              UNREADABLE_METADATA
            end

            def meta_value(meta, key)
              return nil unless meta.is_a?(Hash)

              meta[key]
            end

            def normalize_author(value)
              if value.is_a?(Array)
                names = value.filter_map do |item|
                  sanitized = sanitize_text(item)
                  sanitized unless sanitized.empty?
                end
                names.join(', ')
              else
                sanitize_text(value)
              end
            end

            def display_title(meta_title:, fallback_name:)
              raw = meta_title || fallback_name || 'Unknown'
              sanitized = sanitize_text(raw)
              sanitized.empty? ? 'Unknown' : sanitized
            end

            def sanitize_text(value)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(
                value.to_s,
                preserve_newlines: false,
                preserve_tabs: false
              ).strip
            end

            def selected_index(total)
              return 0 if total <= 0

              current = (menu_state_reader&.browse_selected || 0).to_i
              current.clamp(0, total - 1)
            end

            def footer_text
              total = @filtered_epubs.length
              query = sanitize_text(menu_state_reader&.search_query)
              return "#{total} #{total == 1 ? 'book' : 'books'}" if query.empty?

              "Filter: #{query}"
            end

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end

            def menu_session_mutator
              @menu_session_mutator ||= @dependencies&.menu_session_mutator
            end
          end
        end
      end
    end
  end
end
