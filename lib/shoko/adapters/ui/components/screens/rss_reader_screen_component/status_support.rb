# frozen_string_literal: true

require 'time'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Header, footer, status, and pane label helpers for the RSS reader screen.
          module RssReaderScreenComponentStatusSupport
            private

            def render_status_row(surface, bounds, layout)
              MenuDesign::StatusRenderer.new(surface, bounds, tokens: @tokens).render_status(
                row: layout[:status_row],
                indent: layout[:indent],
                left: status_message,
                right: status_detail,
                width: layout[:content_width],
                left_color: status_color
              )
            end

            def status_message
              menu_state_reader&.rss_message.to_s
            end

            def status_detail
              [scope_label, last_synced_label].reject(&:empty?).join('  |  ')
            end

            def status_color
              case menu_state_reader&.rss_status&.to_sym
              when :error then @tokens.error
              when :syncing then @tokens.accent
              when :ready then @tokens.success
              else @tokens.dim
              end
            end

            def header_hint
              return 'ENTER apply  ESC back' if overlay_mode?
              return 'Z zen  H/L pane  J/K move  Q menu' if zen_mode?

              'TAB pane  J/K move  S sync  A add  / filter'
            end

            def footer_text
              return 'Subscribe to a feed URL and press Enter' if feed_input_mode?
              return 'Live filter is active while you type' if filter_mode?
              return '1/2/3 scope  R read  U unread  M star  V unstar  Z exit zen' if zen_mode?

              '1/2/3 scope  R read  U unread  M star  V unstar  D remove feed  Q menu'
            end

            def pane_border_color(focus)
              normalized_focus == focus ? ui_border_accent : ui_border_primary
            end

            def pane_label_color(focus)
              normalized_focus == focus ? @tokens.accent : @tokens.primary
            end

            def list_row_color(item)
              return @tokens.error if item.is_a?(Hash) && item[:sync_error].to_s != ''

              @tokens.primary
            end

            def article_box_label
              title = current_feed_title
              return 'Articles' if title.empty?

              "Articles · #{title}"
            end

            def content_box_label
              article = selected_article_hash
              return 'Content' unless article

              "Content · #{article[:feed_title]}"
            end

            def zen_box_label
              article = selected_article_hash
              article ? "Zen · #{article[:title]}" : 'Zen'
            end

            def current_feed_title
              feed = feed_entries[current_feed_index]
              feed ? feed[:title].to_s : ''
            end

            def scope_label
              case menu_state_reader&.rss_scope&.to_sym
              when :unread then 'Unread'
              when :starred then 'Starred'
              else 'All'
              end
            end

            def last_synced_label
              text = menu_state_reader&.rss_last_synced_at.to_s.strip
              return '' if text.empty?

              "Synced #{Time.parse(text).localtime.strftime('%Y-%m-%d %H:%M')}"
            rescue ArgumentError
              unknown_last_synced_label
            end

            def ui_border_accent
              Shoko::Adapters::Ui::Constants::Ui::BORDER_ACCENT
            end

            def ui_border_primary
              Shoko::Adapters::Ui::Constants::Ui::BORDER_PRIMARY
            end

            def unknown_last_synced_label
              ''
            end
          end
        end
      end
    end
  end
end
