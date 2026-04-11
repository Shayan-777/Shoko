# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class RssReader
            # Shared focus and selection helpers for the RSS reader action group.
            module FocusFlow
              private

              def move_focus(delta)
                current_index = FOCUS_ORDER.index(normalized_focus) || 0
                next_index = (current_index + delta) % FOCUS_ORDER.length
                update_menu(rss_focus: FOCUS_ORDER[next_index])
              end

              def activate_selection
                case normalized_focus
                when :feeds
                  update_menu(rss_focus: :articles, rss_content_scroll: 0)
                when :articles
                  article = selected_article
                  return unless article

                  update_menu(rss_focus: :content, rss_content_scroll: 0)
                  update_selected_article_read(true) unless article[:read] == true
                when :content
                  update_menu(rss_focus: :feeds)
                end
              end

              def normalized_focus
                focus = current_menu.rss_focus&.to_sym
                FOCUS_ORDER.include?(focus) ? focus : :feeds
              end

              def rss_feeds
                Array(current_menu.rss_feeds)
              end

              def rss_articles
                Array(current_menu.rss_articles)
              end

              def current_feed_index
                preferred = current_menu.rss_selected_feed_key.to_s
                rss_feeds.index { |feed| feed[:key].to_s == preferred } || 0
              end

              def current_article_index
                preferred = current_menu.rss_selected_article_id.to_s
                rss_articles.index { |article| article[:id].to_s == preferred } || 0
              end

              def selected_article
                rss_articles[current_article_index]
              end
            end
          end
        end
      end
    end
  end
end
