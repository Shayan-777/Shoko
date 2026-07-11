# frozen_string_literal: true

require_relative '../base_component'
require 'shoko/shared/terminal/text_sanitizer'
require 'shoko/application/ports/inbound/menu_catalog'
require 'shoko/shared/language_directory'
require 'shoko/adapters/translation/engine_locator'
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
          # Translator settings + language-pack catalog: backend and engine
          # rows up top, then the downloadable Firefox-translation-model
          # packs beneath their own dim heading — the same canvas grammar as
          # the dictionary settings screen. Pack search lives in the status
          # bar; download progress rides an accent stroke under the status
          # line.
          class TranslatorPacksScreenComponent < BaseComponent
            include Ui::TextUtils

            Palette = StatusBar::Palette

            ActionItem = Data.define(:key, :label, :value, :action)

            ACTION_VALUE_HELPERS = {
              back_value: :back_value,
              backend_value: :backend_value,
              engine_value: :engine_value,
              refresh_value: :refresh_value,
            }.freeze

            def initialize(dependencies: nil, menu_visual_profile: nil)
              super()
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
              @config_reader = nil
            end

            def do_render(surface, bounds)
              frame = MenuDesign::CanvasFrame.new(surface, bounds)
              frame.paint
              frame.render_rule(title: 'Translator', accent: accent, meta: rule_meta)
              list = MenuDesign::CanvasList.new(surface, bounds, frame: frame, hits: hits)
              list.register_wheel(top: frame.body_top, height: frame.body_height,
                                  action: { type: :list_wheel, list: :translator_packs })
              packs_top = render_actions(list, frame)
              render_packs(list, frame, packs_top)
              frame.render_hint(hint_text)
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def accent
              MenuDesign::ViewAccents.for(:translator)
            end

            def hits
              @dependencies&.menu_hit_registry
            end

            def rule_meta
              backend_local? ? 'on-device' : 'libretranslate'
            end

            def hint_text
              return 'type to filter · ENTER apply · ESC back' if search_active?

              'ENTER download/remove · / search packs · R refresh · ESC back'
            end

            # ----- settings rows -----

            def render_actions(list, frame)
              row = frame.body_top
              action_items.each_with_index do |item, index|
                break if row > frame.body_bottom

                render_action_row(list, frame, item: item, index: index, row: row)
                row += 1
              end
              row + 1
            end

            def render_action_row(list, frame, item:, index:, row:)
              selected = selected_index == index
              label_fg = selected ? Palette::LANDING_TITLE_FG : Palette::LANDING_TEXT_FG
              list.row(
                row: row,
                left: [[item.label.to_s, label_fg]],
                right: [[item.value.to_s, action_value_fg(item)]],
                selected: selected,
                action: { type: :list_row, list: :translator_packs, index: index },
                width: frame.content_width
              )
            end

            def action_value_fg(item)
              return Palette::LANDING_QUIT_FG if item.value.to_s.include?('Not built')
              return accent if item.key == :backend

              Palette::LANDING_DIM_FG
            end

            # ----- pack list -----

            def render_packs(list, frame, top)
              return if top > frame.body_bottom

              frame.write_line(top, [['LANGUAGE PACKS', Palette::LANDING_DIM_FG],
                                     ["  #{status_label}", status_fg]])
              render_progress(frame, top + 1) if packs_progress.positive?
              render_pack_rows(list, frame, top + 2)
            end

            def render_progress(frame, row)
              return if row > frame.body_bottom

              width = [frame.content_width / 2, 12].max
              filled = (packs_progress.clamp(0.0, 1.0) * width).round
              frame.write_line(row, [
                                 ['━' * filled, accent],
                                 ['━' * (width - filled), Palette::FAINT_FG],
                                 ["  #{(packs_progress * 100).round}%", Palette::LANDING_DIM_FG],
                               ])
            end

            def render_pack_rows(list, frame, top)
              height = [frame.body_bottom - top + 1, 0].max
              return if height <= 0

              items = filtered_results
              return render_packs_empty(frame, top, height) if items.empty?

              window = packs_window(items, height)
              window[:items].each_with_index do |item, offset|
                render_pack_row(list, frame, item: item, position: window[:start] + offset, row: top + offset)
              end
              list.render_scrollbar(top: top, height: height, total: items.length,
                                    visible: height, offset: window[:start])
            end

            def render_pack_row(list, frame, item:, position:, row:)
              absolute = action_items.length + position
              selected = selected_index == absolute
              list.row(
                row: row,
                left: pack_row_segments(item, selected),
                right: [[item[:installed] ? 'installed' : 'download',
                         item[:installed] ? Palette::TRANS_ACCENT_FG : Palette::LANDING_DIM_FG]],
                selected: selected,
                action: { type: :list_row, list: :translator_packs, index: absolute },
                width: frame.content_width
              )
            end

            def pack_row_segments(item, selected)
              pair_fg = selected ? Palette::LANDING_TITLE_FG : accent
              [
                [item[:installed] ? '● ' : '○ ', item[:installed] ? Palette::TRANS_ACCENT_FG : Palette::FAINT_FG],
                [format_pair(item), pair_fg],
                ["   #{format_size(item[:size])}", Palette::LANDING_DIM_FG],
              ]
            end

            def render_packs_empty(frame, top, height)
              frame.write_line(top + [height / 2, 0].max, [[empty_state_message, empty_state_fg]])
            end

            def packs_window(items, height)
              selection = [selected_index - action_items.length, 0].max
              start_index, visible = Ui::ListWindowing.slice_visible(items, height, selection)
              { start: start_index, items: visible }
            end

            # ----- state + labels -----

            def packs_results
              menu_state_reader&.translator_packs_results || []
            end

            def filtered_results
              query = packs_query.downcase
              return packs_results if query.empty?

              packs_results.select do |item|
                pair = "#{item[:from]}-#{item[:to]}".downcase
                names = "#{language_name(item[:from])} #{language_name(item[:to])}".downcase
                pair.include?(query) || names.include?(query)
              end
            end

            def format_pair(item)
              "#{language_name(item[:from])} → #{language_name(item[:to])}"
            end

            def language_name(code)
              Shoko::Shared::LanguageDirectory.name_for(code)
            end

            def format_size(bytes)
              mib = bytes.to_i / (1024.0 * 1024.0)
              format('%.0f MB', mib)
            end

            def selected_index
              (menu_state_reader&.translator_packs_selected || 0).to_i
            end

            def packs_query
              menu_state_reader&.translator_packs_query.to_s
            end

            def search_active?
              (menu_state_reader&.mode || :translator_packs).to_sym == :translator_packs_search
            end

            def packs_status
              (menu_state_reader&.translator_packs_status || :idle).to_sym
            end

            def packs_message
              menu_state_reader&.translator_packs_message.to_s
            end

            def packs_progress
              (menu_state_reader&.translator_packs_progress || 0.0).to_f
            end

            def status_label
              return 'Loading…' if packs_status == :loading
              return packs_message if %i[downloading error].include?(packs_status)

              message = packs_message.strip
              return message unless message.empty?

              count = filtered_results.length
              query = safe_text(packs_query).strip
              return "#{count} language packs" if query.empty?

              "#{count} for “#{query}”"
            end

            def status_fg
              case packs_status
              when :error then Palette::LANDING_QUIT_FG
              when :loading, :downloading then Palette::LIST_MATCH_FG
              else Palette::LANDING_DIM_FG
              end
            end

            def empty_state_message
              return 'Loading language pack list…' if packs_status == :loading
              return packs_message if packs_status == :error
              return 'No results for your search' unless packs_query.strip.empty?

              'Press R to fetch the catalog'
            end

            def empty_state_fg
              return Palette::LANDING_QUIT_FG if packs_status == :error
              return Palette::LIST_MATCH_FG if packs_status == :loading

              Palette::LANDING_DIM_FG
            end

            # ----- setting values -----

            def action_items
              Shoko::Application::Ports::Inbound::MenuCatalog.translator_packs_action_items.map do |item|
                ActionItem.new(
                  key: item.key,
                  label: item.label,
                  value: action_value_for(item.value_key),
                  action: item.action
                )
              end
            end

            def action_value_for(value_key)
              helper = ACTION_VALUE_HELPERS[value_key.to_sym]
              helper ? send(helper) : ''
            end

            def back_value
              'Return'
            end

            def backend_local?
              config_reader&.translator_backend.to_s != 'libretranslate'
            end

            def backend_value
              backend_local? ? 'On-device (local)' : 'LibreTranslate server'
            end

            def engine_value
              return 'Ready' if Shoko::Adapters::Translation::EngineLocator.available?

              "Not built — #{Shoko::Adapters::Translation::EngineLocator::BUILD_HINT}"
            end

            def refresh_value
              packs_status == :loading ? 'Loading…' : 'Fetch latest list'
            end

            def safe_text(text)
              Shoko::Shared::Terminal::TextSanitizer.sanitize(
                text.to_s, preserve_newlines: false, preserve_tabs: false
              )
            end

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end

            def config_reader
              @config_reader ||= @dependencies&.config_reader
            end
          end
        end
      end
    end
  end
end
