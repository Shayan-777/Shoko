# frozen_string_literal: true

require_relative '../base_component'
require_relative '../rect'
require 'shoko/application/ports/inbound/menu_catalog'
require 'shoko/shared/download_source_policy'
require 'shoko/shared/theme_policy'
require_relative '../menu_design/canvas_frame'
require_relative '../menu_design/canvas_list'
require_relative '../menu_design/canvas_well'
require_relative '../menu_design/icon_set'
require_relative '../menu_design/view_accents'
require_relative '../status_bar/palette'
require_relative '../ui/list_helpers'
require_relative '../ui/text_utils'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Settings — every preference as a label · value row on the canvas
          # with the family's selection strip, and a raised inspector well
          # beside the list describing the highlighted setting (what it does,
          # its options, how to change it). Wipe-cache flags keep their
          # checkbox glyphs; armed values pick up the amber warning tone.
          class SettingsScreenComponent < BaseComponent
            include Ui::TextUtils

            Palette = StatusBar::Palette

            SETTINGS_ITEMS = Shoko::Application::Ports::Inbound::MenuCatalog.settings_items

            CHECKBOX_UNCHECKED = '󰄱'
            CHECKBOX_CHECKED = '󰱒'
            WELL_WIDTH = 36
            WELL_GAP = 2
            WIPE_CACHE_TOGGLE_ACTIONS = {
              toggle_wipe_cache_cached: :wipe_cache_cached,
              toggle_wipe_cache_downloads: :wipe_cache_downloads,
              toggle_wipe_cache_dictionary: :wipe_cache_dictionary,
              toggle_wipe_cache_annotations: :wipe_cache_annotations,
              toggle_wipe_cache_bookmarks: :wipe_cache_bookmarks,
              toggle_wipe_cache_progress: :wipe_cache_progress,
              toggle_wipe_cache_config: :wipe_cache_config,
              toggle_wipe_cache_nuke: :wipe_cache_nuke,
            }.freeze
            SETTING_DETAILS = {
              back_to_menu: {
                description: 'Return to the main menu.',
                controls: 'Enter or Space returns immediately.',
              },
              toggle_view_mode: {
                description: 'Choose whether the reader shows one page or a two-page spread.',
                controls: 'Enter or Space toggles the mode.',
                options: %w[Single Split],
              },
              cycle_line_spacing: {
                description: 'Control how dense the reading layout feels.',
                controls: 'Enter or Space cycles the spacing.',
                options: %w[Normal Relaxed Compact],
              },
              cycle_paragraph_style: {
                description: 'Book follows each book\'s own paragraph design; Spaced forces blank lines ' \
                             'between paragraphs; Indent forces continuous first-line-indented prose.',
                controls: 'Enter or Space cycles the style.',
                options: %w[Book Spaced Indent],
              },
              cycle_justify: {
                description: 'Book justifies only where the book asks for it; On justifies all body text ' \
                             'to both margins; Off keeps a ragged right edge everywhere.',
                controls: 'Enter or Space cycles justification.',
                options: %w[Book On Off],
              },
              toggle_book_colors: {
                description: 'Render colors the book itself specifies (info boxes, colored inlines). ' \
                             'Turn off to keep the theme palette only.',
                controls: 'Enter or Space toggles book colors.',
              },
              cycle_download_source: {
                description: 'Select which remote catalog powers the download screen.',
                controls: 'Enter or Space cycles the source.',
                options: %w[Gutendex Libgen],
              },
              cycle_theme: {
                description: 'Change the palette used across menus and reading surfaces.',
                controls: 'Enter or Space advances to the next theme.',
              },
              toggle_page_numbering_mode: {
                description: 'Choose between absolute document pages and dynamic paginated pages.',
                controls: 'Enter or Space toggles the mode.',
                options: %w[Absolute Dynamic],
              },
              toggle_page_numbers: {
                description: 'Show or hide page numbers in the reader footer.',
                controls: 'Enter or Space toggles page numbers.',
              },
              toggle_highlight_quotes: {
                description: 'Emphasize quoted passages while rendering text.',
                controls: 'Enter or Space toggles quote highlighting.',
              },
              open_dictionary_settings: {
                description: 'Open dictionary catalog, download, and lookup settings.',
                controls: 'Enter or Space opens dictionary settings.',
              },
              toggle_kitty_images: {
                description: 'Enable inline images when Kitty graphics are supported.',
                controls: 'Enter or Space toggles image rendering.',
              },
              toggle_prepaginate_on_resize: {
                description: 'On startup, pre-paginate cached books in the background after the terminal ' \
                             'size changes, so opening any book is instant. Off by default — leave off to ' \
                             'recalculate each book only when you open it.',
                controls: 'Enter or Space toggles pre-pagination.',
              },
              wipe_cache: {
                description: 'Delete cached data using the flags listed below. Review carefully before running.',
                controls: 'Enter or Space executes the wipe.',
              },
              toggle_wipe_cache_cached: {
                description: 'Include cached payloads and pagination data in the wipe.',
                controls: 'Enter or Space toggles this flag.',
              },
              toggle_wipe_cache_downloads: {
                description: 'Include downloaded books in the wipe.',
                controls: 'Enter or Space toggles this flag.',
              },
              toggle_wipe_cache_dictionary: {
                description: 'Include downloaded dictionaries in the wipe. Left off (and excluded from Nuke) ' \
                             'so they survive a wipe instead of being re-downloaded.',
                controls: 'Enter or Space toggles this flag.',
              },
              toggle_wipe_cache_annotations: {
                description: 'Include saved annotations in the wipe.',
                controls: 'Enter or Space toggles this flag.',
              },
              toggle_wipe_cache_bookmarks: {
                description: 'Include saved bookmarks in the wipe.',
                controls: 'Enter or Space toggles this flag.',
              },
              toggle_wipe_cache_progress: {
                description: 'Include reading progress snapshots in the wipe.',
                controls: 'Enter or Space toggles this flag.',
              },
              toggle_wipe_cache_config: {
                description: 'Include the saved configuration file in the wipe.',
                controls: 'Enter or Space toggles this flag.',
              },
              toggle_wipe_cache_nuke: {
                description: 'Arm a full reset. This enables every wipe flag except Dictionaries, ' \
                             'which stays under its own toggle so downloads survive.',
                controls: 'Enter or Space toggles the nuke flag.',
              },
            }.freeze
            EMPTY_SETTING_DETAIL = {}.freeze

            PREFERENCE_VALUE_HELPERS = {
              toggle_view_mode: :view_mode_value,
              cycle_line_spacing: :line_spacing_value,
              cycle_paragraph_style: :paragraph_style_value,
              cycle_justify: :justify_value,
              toggle_book_colors: :book_colors_value,
              cycle_download_source: :download_source_value,
              cycle_theme: :theme_value,
              toggle_page_numbering_mode: :page_numbering_mode_value,
              toggle_page_numbers: :page_numbers_value,
              toggle_highlight_quotes: :highlight_quotes_value,
              toggle_kitty_images: :kitty_images_value,
              toggle_prepaginate_on_resize: :prepaginate_on_resize_value,
            }.freeze

            def initialize(catalog_service = nil, dependencies: nil, menu_visual_profile: nil)
              super()
              @catalog = catalog_service
              @dependencies = dependencies
              @menu_visual_profile = menu_visual_profile
              @menu_state_reader = nil
              @config_reader = nil
            end

            def do_render(surface, bounds)
              frame = MenuDesign::CanvasFrame.new(surface, bounds)
              frame.paint
              selection = selected_setting_payload
              frame.render_rule(title: 'Settings', accent: accent, meta: "theme: #{current_theme_id}")
              render_list(surface, bounds, frame, selection)
              render_detail_well(surface, bounds, frame, selection) if well_visible?(frame)
              frame.render_hint('ENTER apply · wheel scrolls · ESC back')
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def accent
              MenuDesign::ViewAccents.for(:settings)
            end

            def hits
              @dependencies&.menu_hit_registry
            end

            def well_visible?(frame)
              frame.content_width >= 78
            end

            def list_width(frame)
              return frame.content_width unless well_visible?(frame)

              [frame.content_width - WELL_WIDTH - WELL_GAP, 30].max
            end

            def render_list(surface, bounds, frame, selection)
              top = frame.body_top
              height = frame.body_height
              return if height <= 0

              list = MenuDesign::CanvasList.new(surface, bounds, frame: frame, hits: hits)
              list.register_wheel(top: top, height: height, action: { type: :list_wheel, list: :settings })
              start_index, visible = Ui::ListHelpers.slice_visible(SETTINGS_ITEMS, height, selection[:index])
              visible.each_with_index do |item, offset|
                render_row(list, frame, item: item, index: start_index + offset,
                                        row: top + offset, selected: start_index + offset == selection[:index])
              end
            end

            def render_row(list, frame, item:, index:, row:, selected:)
              value_text, value_fg = display_value_for(item.action)
              label_fg = selected ? Palette::LANDING_TITLE_FG : Palette::LANDING_TEXT_FG
              list.row(
                row: row,
                left: [[label_text(item), label_fg]],
                right: [[value_text, value_fg]],
                selected: selected,
                action: { type: :list_row, list: :settings, index: index },
                width: list_width(frame)
              )
            end

            # ----- inspector well -----

            def render_detail_well(surface, bounds, frame, selection)
              rect = Components::Rect.new(
                x: frame.content_x + frame.content_width - WELL_WIDTH,
                y: frame.body_top,
                width: WELL_WIDTH,
                height: [frame.body_height, 4].max
              )
              well = MenuDesign::CanvasWell.new(surface, bounds, rect: rect)
              well.paint(title: selection[:item].label, accent: Palette::LANDING_POINTER_FG)
              well_lines(selection, well.inner_width).each_with_index do |segments, offset|
                break if offset >= well.inner_height

                well.write_line(offset, segments)
              end
            end

            def well_lines(selection, width)
              detail = selection_detail(selection[:item].action)
              rows = [[[selection[:value_text], selection[:value_color]]], []]
              rows + wrapped_well_text(detail, width)
            end

            def wrapped_well_text(detail, width)
              rows = wrap_words(detail.fetch(:description, ''), width).map { |line| [[line, nil]] }
              options = Array(detail[:options])
              unless options.empty?
                rows << []
                rows << [['OPTIONS', Palette::LANDING_DIM_FG]]
                rows += wrap_words(options.join(' · '), width).map { |line| [[line, Palette::LANDING_DIM_FG]] }
              end
              rows << []
              rows += wrap_words(detail.fetch(:controls, ''), width).map { |line| [[line, Palette::LANDING_DIM_FG]] }
              rows
            end

            def selection_detail(action)
              SETTING_DETAILS.fetch(action, EMPTY_SETTING_DETAIL)
            end

            def selected_setting_payload
              index = selected_index
              item = SETTINGS_ITEMS[index] || SETTINGS_ITEMS.first
              value_text, value_color = display_value_for(item.action)
              { index: index, item: item, value_text: value_text, value_color: value_color }
            end

            def selected_index
              current = (menu_state_reader&.settings_selected || 1).to_i
              current.clamp(0, SETTINGS_ITEMS.length - 1)
            end

            def label_text(item)
              wipe_key = WIPE_CACHE_TOGGLE_ACTIONS[item.action]
              return item.label unless wipe_key

              "#{checkbox_glyph(wipe_cache_checked?(wipe_key))} #{item.label}"
            end

            def checkbox_glyph(selected)
              if MenuDesign::IconSet.ascii_icons?
                selected ? '[x]' : '[ ]'
              else
                selected ? CHECKBOX_CHECKED : CHECKBOX_UNCHECKED
              end
            end

            def wipe_cache_checked?(key)
              reader = menu_state_reader
              return false unless reader

              reader.public_send("#{key}?")
            end

            # ----- values (family tones: emerald on, amber armed/off-warn) -----

            def display_value_for(action)
              static_value_for(action) ||
                preference_value_for(action) ||
                wipe_cache_toggle_value(action) ||
                ['—', Palette::LANDING_DIM_FG]
            end

            def static_value_for(action)
              case action
              when :back_to_menu then ['Return', Palette::LANDING_DIM_FG]
              when :open_dictionary_settings then ['Open', Palette::LANDING_DIM_FG]
              when :wipe_cache then ['Run', Palette::LIST_MATCH_FG]
              end
            end

            def preference_value_for(action)
              helper = PREFERENCE_VALUE_HELPERS[action]
              helper && send(helper)
            end

            def wipe_cache_toggle_value(action)
              return nil unless WIPE_CACHE_TOGGLE_ACTIONS.key?(action)

              armed = wipe_cache_checked?(WIPE_CACHE_TOGGLE_ACTIONS.fetch(action))
              [armed ? 'Armed' : 'Off', armed ? Palette::LIST_MATCH_FG : Palette::LANDING_DIM_FG]
            end

            def accent_value(text)
              [text, Palette::LANDING_POINTER_FG]
            end

            def bool_value(raw, default_truthy, true_text:, false_text:)
              enabled = raw.nil? ? default_truthy : raw == true
              [enabled ? true_text : false_text,
               enabled ? Palette::TRANS_ACCENT_FG : Palette::LANDING_DIM_FG]
            end

            def humanize_symbol(value)
              value.to_s.split('_').map(&:capitalize).join(' ')
            end

            def current_theme_id
              Shoko::Shared::ThemePolicy.normalize(config_reader&.theme) || Shoko::Shared::ThemePolicy.default_id
            end

            def view_mode_value
              accent_value(humanize_symbol(config_reader&.view_mode || :single))
            end

            def line_spacing_value
              accent_value(humanize_symbol(config_reader&.line_spacing || :normal))
            end

            def paragraph_style_value
              accent_value(humanize_symbol(config_reader&.paragraph_style || :book))
            end

            def justify_value
              accent_value(humanize_symbol(config_reader&.justify || :book))
            end

            def book_colors_value
              bool_value(config_reader&.book_colors, true, true_text: 'Enabled', false_text: 'Disabled')
            end

            def download_source_value
              source = Shoko::Shared::DownloadSourcePolicy.normalize(config_reader&.download_source) ||
                       Shoko::Shared::DownloadSourcePolicy.default_id
              accent_value(Shoko::Shared::DownloadSourcePolicy.label_for(source))
            end

            def theme_value
              accent_value(humanize_symbol(current_theme_id))
            end

            def page_numbering_mode_value
              accent_value(humanize_symbol(config_reader&.page_numbering_mode || :dynamic))
            end

            def page_numbers_value
              bool_value(config_reader&.show_page_numbers, true, true_text: 'Enabled', false_text: 'Disabled')
            end

            def highlight_quotes_value
              bool_value(config_reader&.highlight_quotes, true, true_text: 'On', false_text: 'Off')
            end

            def kitty_images_value
              bool_value(config_reader&.kitty_images, false, true_text: 'Enabled', false_text: 'Disabled')
            end

            def prepaginate_on_resize_value
              bool_value(config_reader&.prepaginate_on_resize, false, true_text: 'On', false_text: 'Off')
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
