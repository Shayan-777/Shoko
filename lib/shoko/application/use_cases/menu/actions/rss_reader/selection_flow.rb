# frozen_string_literal: true

module Shoko
  module Application
    module UseCases
      module Menu
        module Actions
          class RssReader
            # Shared cursor, scope, and article mutation helpers for RSS actions.
            module SelectionFlow
              private

              def move_cursor(delta)
                case normalized_focus
                when :feeds
                  move_feed_selection(delta)
                when :articles
                  move_article_selection(delta)
                when :content
                  scroll_content(delta)
                end
              end

              def page_move(direction)
                case normalized_focus
                when :feeds
                  move_feed_selection(direction * 6)
                when :articles
                  move_article_selection(direction * 8)
                when :content
                  scroll_content(direction * 12)
                end
              end

              def move_to_boundary(boundary)
                return move_feed_to_boundary(boundary) if normalized_focus == :feeds
                return move_article_to_boundary(boundary) if normalized_focus == :articles

                move_content_to_boundary(boundary)
              end

              def move_feed_selection(delta)
                return if rss_feeds.empty?

                current_index = current_feed_index
                next_index = (current_index + delta).clamp(0, rss_feeds.length - 1)
                select_feed(rss_feeds[next_index][:key])
              end

              def move_article_selection(delta)
                return if rss_articles.empty?

                current_index = current_article_index
                next_index = (current_index + delta).clamp(0, rss_articles.length - 1)
                select_article(rss_articles[next_index][:id])
              end

              def select_feed(feed_key)
                return if feed_key.to_s.strip.empty?

                @rss_reader_workflow.refresh_rss_reader(
                  preferred_feed_key: feed_key,
                  preferred_article_id: nil,
                  reset_content: true
                )
              end

              def select_article(article_id)
                return if article_id.to_s.strip.empty?

                update_menu(rss_selected_article_id: article_id.to_s, rss_content_scroll: 0)
              end

              def scroll_content(delta)
                next_value = (current_menu.rss_content_scroll || 0).to_i + delta.to_i
                update_menu(rss_content_scroll: [next_value, 0].max)
              end

              def update_scope(scope)
                update_menu(rss_scope: scope)
                @rss_reader_workflow.refresh_rss_reader(reset_content: true)
              end

              def toggle_zen_mode
                next_zen_mode = current_menu.rss_zen_mode != true
                payload = { rss_zen_mode: next_zen_mode }

                if next_zen_mode
                  article = selected_article || rss_articles.first
                  payload[:rss_focus] = :content
                  payload[:rss_selected_article_id] = article[:id] if article
                elsif normalized_focus == :content
                  payload[:rss_focus] = :articles
                end

                update_menu(payload)
              end

              def update_selected_article_read(read)
                article = selected_article
                return unless article

                @rss_reader_workflow.set_rss_article_read(article[:id], read: read)
              end

              def update_selected_article_starred(starred)
                article = selected_article
                return unless article

                @rss_reader_workflow.set_rss_article_starred(article[:id], starred: starred)
              end

              def remove_selected_feed
                @rss_reader_workflow.remove_rss_feed(current_menu.rss_selected_feed_key)
              end

              def move_feed_to_boundary(boundary)
                target = boundary == :top ? rss_feeds.first : rss_feeds.last
                select_feed(target && target[:key])
              end

              def move_article_to_boundary(boundary)
                target = boundary == :top ? rss_articles.first : rss_articles.last
                select_article(target && target[:id])
              end

              def move_content_to_boundary(boundary)
                update_menu(rss_content_scroll: boundary == :top ? 0 : 100_000)
              end
            end
          end
        end
      end
    end
  end
end
