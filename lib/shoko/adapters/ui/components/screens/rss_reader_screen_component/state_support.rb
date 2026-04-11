# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Menu-state readers and derived selection helpers for the RSS reader screen.
          module RssReaderScreenComponentStateSupport
            private

            def feed_entries
              Array(menu_state_reader&.rss_feeds)
            end

            def article_entries
              Array(menu_state_reader&.rss_articles)
            end

            def selected_article_hash
              article_entries[current_article_index]
            end

            def current_feed_index
              selected_index_for(feed_entries, :key, menu_state_reader&.rss_selected_feed_key)
            end

            def current_article_index
              selected_index_for(article_entries, :id, menu_state_reader&.rss_selected_article_id)
            end

            def current_scroll
              (menu_state_reader&.rss_content_scroll || 0).to_i
            end

            def normalized_focus
              focus = menu_state_reader&.rss_focus&.to_sym
              return focus if %i[feeds articles content].include?(focus)

              :feeds
            end

            def overlay_mode?
              feed_input_mode? || filter_mode?
            end

            def feed_input_mode?
              menu_state_reader&.mode == :rss_reader_feed_input
            end

            def filter_mode?
              menu_state_reader&.mode == :rss_reader_filter
            end

            def zen_mode?
              menu_state_reader&.rss_zen_mode == true
            end

            def menu_state_reader
              @menu_state_reader ||= @dependencies&.menu_state_reader
            end

            def selected_index_for(items, key, preferred)
              preferred_value = preferred.to_s
              items.index { |item| item[key].to_s == preferred_value } || 0
            end
          end
        end
      end
    end
  end
end
