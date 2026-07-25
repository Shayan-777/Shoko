# frozen_string_literal: true

require 'shoko/shared/hash_normalizer'
require_relative '../base_component'
require 'shoko/shared/download_source_policy'
require 'shoko/shared/terminal/text_sanitizer'
require_relative '../menu_design/canvas_frame'
require_relative '../menu_design/canvas_list'
require_relative '../menu_design/view_accents'
require_relative '../status_bar/palette'
require_relative '../ui/text_utils'
require_relative '../ui/list_windowing'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Download Books — remote search results as two-row blocks (title,
          # then authors · language with the source-specific meta on the
          # right), cyan like the dictionary family. The query lives in the
          # status bar; TAB raises the source picker as a small candidate list
          # under the rule; search/download progress rides an accent stroke on
          # the status line.
          class DownloadBooksScreenComponent < BaseComponent
            HashNormalizer = Shoko::Shared::HashNormalizer

            TextSanitizer = Shoko::Shared::Terminal::TextSanitizer

            include Ui::TextUtils

            Palette = StatusBar::Palette

            ROWS_PER_RESULT = 2

            def initialize(menu_state_reader: nil, config_reader: nil, menu_hit_registry: nil, menu_visual_profile: nil)
              super()
              @menu_state_reader = menu_state_reader
              @config_reader = config_reader
              @menu_hit_registry = menu_hit_registry
              @menu_visual_profile = menu_visual_profile
            end

            def do_render(surface, bounds)
              frame = MenuDesign::CanvasFrame.new(surface, bounds)
              frame.paint
              frame.render_rule(title: 'Download Books', accent: accent, meta: rule_meta)
              list = MenuDesign::CanvasList.new(surface, bounds, frame: frame, hits: hits)
              render_status_line(frame)
              body_top = frame.body_top + 2
              body_top = render_source_picker(list, frame, body_top) if source_selection_active?
              render_results(list, frame, body_top)
              frame.render_hint(hint_text)
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def accent
              MenuDesign::ViewAccents.for(:download)
            end

            def hits
              @menu_hit_registry
            end

            def rule_meta
              "source: #{current_source_label.downcase} · #{result_count_text.downcase}"
            end

            def hint_text
              return 'j/k choose source · ENTER apply · ESC cancel' if source_selection_active?
              return 'type your query · ENTER search · ESC cancel' if search_active?

              'ENTER download · / search · TAB source · n/p pages · ESC back'
            end

            # ----- status + progress -----

            def render_status_line(frame)
              label, label_fg = status_label
              segments = [[label, label_fg]]
              segments = progress_segments + [['  ', nil], [label, label_fg]] if download_progress.positive?
              frame.write_line(frame.body_top, segments)
            end

            def progress_segments
              width = 18
              filled = (download_progress.clamp(0.0, 1.0) * width).round
              [
                ['━' * filled, accent],
                ['━' * (width - filled), Palette::FAINT_FG],
                ["  #{(download_progress * 100).round}%", Palette::LANDING_DIM_FG],
              ]
            end

            def status_label
              msg = TextSanitizer.single_line(download_message)
              case download_status
              when :searching then [msg.empty? ? "Searching #{current_source_label}…" : msg, Palette::LIST_MATCH_FG]
              when :downloading then [msg.empty? ? 'Downloading…' : msg, Palette::LIST_MATCH_FG]
              when :error then [msg.empty? ? 'Request failed' : msg, Palette::LANDING_QUIT_FG]
              when :done then [msg, Palette::TRANS_ACCENT_FG]
              else [idle_status_text, Palette::LANDING_DIM_FG]
              end
            end

            def idle_status_text
              query = TextSanitizer.single_line(search_query).strip
              query.empty? ? 'Press / and type to search the catalog' : "Results for “#{query}”"
            end

            # ----- source picker -----

            def render_source_picker(list, frame, top)
              source_options.each_with_index do |source, index|
                render_source_option(list, frame, source: source, index: index, row: top + index)
              end
              top + source_options.length + 1
            end

            def render_source_option(list, frame, source:, index:, row:)
              selected = index == selected_source_index
              active = source == current_source
              list.row(
                row: row,
                left: [
                  [active ? '● ' : '○ ', active ? accent : Palette::FAINT_FG],
                  [Shoko::Shared::DownloadSourcePolicy.label_for(source),
                   selected ? Palette::LANDING_TITLE_FG : Palette::LANDING_TEXT_FG],
                ],
                selected: selected,
                action: { type: :list_row, list: :download_source, index: index },
                width: [frame.content_width / 2, 24].max
              )
            end

            # ----- results -----

            def render_results(list, frame, top)
              height = [frame.body_bottom - top + 1, 0].max
              return if height <= 0

              items = results
              return render_empty(frame, top, height) if items.empty?

              list.register_wheel(top: top, height: height, action: { type: :list_wheel, list: :download })
              window = visible_window(items, height)
              render_result_blocks(list, frame, window, top)
              list.render_scrollbar(top: top, height: height, total: items.length,
                                    visible: window[:capacity], offset: window[:start])
            end

            def render_result_blocks(list, frame, window, top)
              window[:items].each_with_index do |book, offset|
                index = window[:start] + offset
                row = top + (offset * ROWS_PER_RESULT)
                break if row + ROWS_PER_RESULT - 1 > frame.body_bottom

                list.block(
                  row: row,
                  lines: result_rows(book, index == selected_index),
                  selected: index == selected_index,
                  action: { type: :list_row, list: :download, index: index }
                )
              end
            end

            def result_rows(book, selected)
              fields = extract_book_fields(book)
              title_fg = selected ? Palette::LANDING_TITLE_FG : Palette::LANDING_TEXT_FG
              meta_label = libgen_result?(book) ? fields[:meta] : "#{fields[:meta]} DLs"
              [
                { left: [[fields[:title], title_fg]] },
                { left: [[secondary_result_line(fields), Palette::LANDING_DIM_FG]],
                  right: [[meta_label, Palette::LANDING_DIM_FG]] },
              ]
            end

            def secondary_result_line(fields)
              [fields[:authors], fields[:languages]].reject(&:empty?).join(' · ')
            end

            def render_empty(frame, top, height)
              message, message_fg = empty_state
              frame.write_line(top + [height / 2, 0].max, [[message, message_fg]])
            end

            def empty_state
              case download_status
              when :searching then ["Searching #{current_source_label}…", Palette::LIST_MATCH_FG]
              when :error then [TextSanitizer.single_line(download_message), Palette::LANDING_QUIT_FG]
              else
                if search_query.strip.empty?
                  ['No search results yet', Palette::LANDING_DIM_FG]
                else
                  ['No results for your search', Palette::LANDING_DIM_FG]
                end
              end
            end

            def visible_window(items, height)
              capacity = [height / ROWS_PER_RESULT, 1].max
              start = if items.length <= capacity
                        0
                      else
                        (selected_index - (capacity / 2)).clamp(0, items.length - capacity)
                      end
              { start: start, items: items[start, capacity] || [], capacity: capacity }
            end

            # ----- state -----

            def results
              menu_state_reader&.download_results || []
            end

            def selected_index
              (menu_state_reader&.download_selected || 0).to_i
            end

            def download_status
              (menu_state_reader&.download_status || :idle).to_sym
            end

            def download_message
              menu_state_reader&.download_message.to_s
            end

            def download_count
              (menu_state_reader&.download_count || 0).to_i
            end

            def download_progress
              (menu_state_reader&.download_progress || 0.0).to_f
            end

            def search_query
              menu_state_reader&.download_query || ''
            end

            def search_active?
              menu_state_reader&.mode == :download_search
            end

            def source_selection_active?
              menu_state_reader&.mode == :download_source_select
            end

            def selected_source_index
              max_index = source_options.length - 1
              (menu_state_reader&.download_source_selected || current_source_index).to_i.clamp(0, max_index)
            end

            def current_source
              Shoko::Shared::DownloadSourcePolicy.normalize(config_reader&.download_source) ||
                Shoko::Shared::DownloadSourcePolicy.default_id
            end

            def current_source_index
              source_options.index(current_source) || 0
            end

            def current_source_label
              Shoko::Shared::DownloadSourcePolicy.label_for(current_source)
            end

            def source_options
              Shoko::Shared::DownloadSourcePolicy.canonical_ids
            end

            def result_count_text
              shown = results.length
              total = download_count
              return "#{shown} of #{total}" if total.positive? && total != shown

              "#{shown} #{shown == 1 ? 'result' : 'results'}"
            end

            # ----- result field extraction -----

            def extract_book_fields(book)
              {
                title: TextSanitizer.single_line(HashNormalizer.indifferent_fetch(book, :title,
                                                                                  'Untitled')),
                authors: TextSanitizer.single_line(Array(HashNormalizer.indifferent_fetch(book,
                                                                                          :authors, [])).join(', ')),
                languages: TextSanitizer.single_line(Array(HashNormalizer.indifferent_fetch(book,
                                                                                            :languages, [])).join(',')),
                meta: result_meta(book),
              }
            end

            def result_meta(book)
              if libgen_result?(book)
                return TextSanitizer.single_line(HashNormalizer.indifferent_fetch(book, :extension,
                                                                                  '').to_s.upcase)
              end

              HashNormalizer.indifferent_fetch(book, :download_count, 0).to_i.to_s
            end

            def libgen_result?(book)
              HashNormalizer.indifferent_fetch(book, :source, current_source) == :libgen
            end

            attr_reader :menu_state_reader, :config_reader
          end
        end
      end
    end
  end
end
