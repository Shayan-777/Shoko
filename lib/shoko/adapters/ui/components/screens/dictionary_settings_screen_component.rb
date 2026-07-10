# frozen_string_literal: true

require_relative '../base_component'
require 'shoko/shared/terminal/text_sanitizer'
require 'shoko/application/ports/inbound/menu_catalog'
require_relative '../menu_design/canvas_frame'
require_relative '../menu_design/canvas_list'
require_relative '../menu_design/view_accents'
require_relative '../status_bar/palette'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Dictionary settings + catalog: the lookup configuration as
          # label · value rows up top, then the downloadable-dictionary
          # catalog beneath its own dim heading — one continuous list in the
          # canvas grammar, cyan like the in-book dictionary card. Catalog
          # search lives in the status bar; download progress rides an accent
          # stroke under the status line.
          class DictionarySettingsScreenComponent < BaseComponent
            include Ui::TextUtils

            Palette = StatusBar::Palette

            ActionItem = Data.define(:key, :label, :value, :action)

            ACTION_VALUE_HELPERS = {
              back_value: :back_value,
              lookup_value: :lookup_value,
              pair_value: :pair_value,
              storage_value: :storage_value,
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
              frame.render_rule(title: 'Dictionary', accent: accent, meta: rule_meta)
              list = MenuDesign::CanvasList.new(surface, bounds, frame: frame, hits: hits)
              list.register_wheel(top: frame.body_top, height: frame.body_height,
                                  action: { type: :list_wheel, list: :dictionary })
              catalog_top = render_actions(list, frame)
              render_catalog(list, frame, catalog_top)
              frame.render_hint(hint_text)
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def accent
              MenuDesign::ViewAccents.for(:dictionary)
            end

            def hits
              @dependencies&.menu_hit_registry
            end

            def rule_meta
              pair_value.downcase
            end

            def hint_text
              return 'type to filter · ENTER apply · ESC back' if search_active?

              'ENTER apply · / search catalog · R refresh · ESC back'
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
                action: { type: :list_row, list: :dictionary, index: index },
                width: frame.content_width
              )
            end

            def action_value_fg(item)
              return Palette::LANDING_QUIT_FG if item.value.to_s.include?('Needs')
              return accent if item.key == :pair

              Palette::LANDING_DIM_FG
            end

            # ----- catalog list -----

            def render_catalog(list, frame, top)
              return if top > frame.body_bottom

              frame.write_line(top, [['CATALOG', Palette::LANDING_DIM_FG],
                                     ["  #{status_label}", status_fg]])
              render_progress(frame, top + 1) if dictionary_progress.positive?
              render_catalog_rows(list, frame, top + 2)
            end

            def render_progress(frame, row)
              return if row > frame.body_bottom

              width = [frame.content_width / 2, 12].max
              filled = (dictionary_progress.clamp(0.0, 1.0) * width).round
              frame.write_line(row, [
                                 ['━' * filled, accent],
                                 ['━' * (width - filled), Palette::FAINT_FG],
                                 ["  #{(dictionary_progress * 100).round}%", Palette::LANDING_DIM_FG],
                               ])
            end

            def render_catalog_rows(list, frame, top)
              height = [frame.body_bottom - top + 1, 0].max
              return if height <= 0

              items = filtered_results
              return render_catalog_empty(frame, top, height) if items.empty?

              window = catalog_window(items, height)
              window[:items].each_with_index do |item, offset|
                render_catalog_row(list, frame, item: item, position: window[:start] + offset, row: top + offset)
              end
              list.render_scrollbar(top: top, height: height, total: items.length,
                                    visible: height, offset: window[:start])
            end

            def render_catalog_row(list, frame, item:, position:, row:)
              absolute = action_items.length + position
              selected = selected_index == absolute
              list.row(
                row: row,
                left: catalog_row_segments(item, selected),
                right: [[item[:installed] ? 'installed' : 'download',
                         item[:installed] ? Palette::TRANS_ACCENT_FG : Palette::LANDING_DIM_FG]],
                selected: selected,
                action: { type: :list_row, list: :dictionary, index: absolute },
                width: frame.content_width
              )
            end

            def catalog_row_segments(item, selected)
              pair_fg = selected ? Palette::LANDING_TITLE_FG : accent
              [
                [item[:installed] ? '● ' : '○ ', item[:installed] ? Palette::TRANS_ACCENT_FG : Palette::FAINT_FG],
                [format_pair(item), pair_fg],
                ["   #{item[:size]}   #{item[:updated]}", Palette::LANDING_DIM_FG],
              ]
            end

            def render_catalog_empty(frame, top, height)
              frame.write_line(top + [height / 2, 0].max, [[empty_state_message, empty_state_fg]])
            end

            def catalog_window(items, height)
              selection = [selected_index - action_items.length, 0].max
              start_index, visible = Ui::ListHelpers.slice_visible(items, height, selection)
              { start: start_index, items: visible }
            end

            # ----- state + labels -----

            def dictionary_results
              menu_state_reader&.dictionary_results || []
            end

            def filtered_results
              query = dictionary_query.downcase
              return dictionary_results if query.empty?

              dictionary_results.select do |item|
                name = item[:name].to_s.downcase
                pair = "#{item[:source]}-#{item[:target]}".downcase
                name.include?(query) || pair.include?(query)
              end
            end

            def format_pair(item)
              src = item[:source].to_s.upcase
              tgt = item[:target].to_s.upcase
              return item[:name].to_s if src.empty? || tgt.empty?

              "#{src} → #{tgt}"
            end

            def selected_index
              (menu_state_reader&.dictionary_selected || 0).to_i
            end

            def dictionary_query
              menu_state_reader&.dictionary_query.to_s
            end

            def search_active?
              (menu_state_reader&.mode || :dictionary).to_sym == :dictionary_search
            end

            def dictionary_status
              (menu_state_reader&.dictionary_status || :idle).to_sym
            end

            def dictionary_message
              menu_state_reader&.dictionary_message.to_s
            end

            def dictionary_progress
              (menu_state_reader&.dictionary_progress || 0.0).to_f
            end

            def status_label
              return 'Loading…' if dictionary_status == :loading
              return dictionary_message if %i[downloading error].include?(dictionary_status)

              message = dictionary_message.strip
              return message unless message.empty?

              count = filtered_results.length
              query = safe_text(dictionary_query).strip
              return "#{count} dictionaries" if query.empty?

              "#{count} for “#{query}”"
            end

            def status_fg
              case dictionary_status
              when :error then Palette::LANDING_QUIT_FG
              when :loading, :downloading then Palette::LIST_MATCH_FG
              else Palette::LANDING_DIM_FG
              end
            end

            def empty_state_message
              return 'Loading dictionary list…' if dictionary_status == :loading
              return dictionary_message if dictionary_status == :error
              return 'No results for your search' unless dictionary_query.strip.empty?

              'Press R to fetch the catalog'
            end

            def empty_state_fg
              return Palette::LANDING_QUIT_FG if dictionary_status == :error
              return Palette::LIST_MATCH_FG if dictionary_status == :loading

              Palette::LANDING_DIM_FG
            end

            # ----- setting values -----

            def action_items
              Shoko::Application::Ports::Inbound::MenuCatalog.dictionary_action_items.map do |item|
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

            def lookup_value
              backend_name = config_reader&.dictionary_backend.to_s.downcase
              runtime_override = runtime_config&.dictionary_backend_override.to_s.downcase
              return 'Disabled' if disabled_dictionary_backend?(backend_name, runtime_override)
              return 'Needs sqlite3' unless dictionary_availability&.sqlite3_available?
              return sqlite3_status if sqlite_dictionary_backend?(backend_name, runtime_override)

              dictionary_auto_status
            end

            def disabled_dictionary_backend?(backend_name, runtime_override)
              runtime_override == 'disabled' || backend_name == 'disabled'
            end

            def sqlite_dictionary_backend?(backend_name, runtime_override)
              runtime_override == 'sqlite' || backend_name == 'sqlite'
            end

            def dictionary_auto_status
              return sqlite3_status if dictionary_datasets_present?

              'Enabled (no datasets)'
            end

            def dictionary_datasets_present?
              dictionary_storage&.databases_present?(config_reader&.dictionary_path)
            end

            def sqlite3_status
              dictionary_availability&.sqlite3_available? ? 'Enabled' : 'Needs sqlite3'
            end

            def pair_value
              source = config_reader&.dictionary_source_lang
              target = config_reader&.dictionary_target_lang
              src = dictionary_auto_setting?(source) ? 'Auto' : source.to_s.upcase
              tgt = target.to_s.strip.empty? ? 'EN' : target.to_s.upcase
              "#{src} → #{tgt}"
            end

            def storage_value
              path = config_reader&.dictionary_path.to_s.strip
              return "Default (#{display_path(default_storage_path)})" if path.empty?

              display_path(path)
            end

            def refresh_value
              dictionary_status == :loading ? 'Loading…' : 'Fetch latest list'
            end

            def runtime_config
              return @runtime_config if defined?(@runtime_config)

              @runtime_config = @dependencies&.runtime_config
            end

            def dictionary_availability
              return @dictionary_availability if defined?(@dictionary_availability)

              @dictionary_availability = @dependencies&.dictionary_availability
            end

            def dictionary_storage
              return @dictionary_storage if defined?(@dictionary_storage)

              @dictionary_storage = @dependencies&.dictionary_storage
            end

            def default_storage_path
              dictionary_storage&.default_databases_path.to_s
            end

            def display_path(path)
              dictionary_storage&.display_path(path).to_s
            end

            def dictionary_auto_setting?(value)
              return true if value.nil?

              str = value.to_s.strip
              str.empty? || str.casecmp('auto').zero?
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
