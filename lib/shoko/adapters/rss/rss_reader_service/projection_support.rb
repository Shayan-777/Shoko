# frozen_string_literal: true

module Shoko
  module Adapters
    module Rss
      # Feed/article projection helpers used by the menu-side RSS reader workflow.
      module RssReaderServiceProjectionSupport
        def feed_projection(snapshot:, scope:)
          normalized_scope = normalize_scope(scope)
          [all_feeds_entry(snapshot[:articles], normalized_scope), *visible_feed_entries(snapshot, normalized_scope)]
        end

        def article_projection(snapshot:, selected_feed_key:, scope:, query:)
          filters = projection_filters(selected_feed_key, scope, query)
          feed_titles = feed_title_index(snapshot)

          filtered_articles(snapshot, filters, feed_titles).map do |article|
            article_projection_entry(article, feed_titles[article.feed_id])
          end
        end

        def normalize_feed_key(feeds:, preferred_key:)
          keys = Array(feeds).map { |feed| feed[:key].to_s }
          preferred = preferred_key.to_s.strip
          return all_feeds_key if keys.empty?
          return preferred if keys.include?(preferred)

          keys.first
        end

        def normalize_article_id(articles:, preferred_id:)
          ids = Array(articles).map { |article| article[:id].to_s }
          preferred = preferred_id.to_s.strip
          return nil if ids.empty?
          return preferred if ids.include?(preferred)

          ids.first
        end

        def last_synced_at(snapshot)
          Array(snapshot[:feeds]).filter_map(&:last_synced_at).max
        end

        private

        def visible_feed_entries(snapshot, scope)
          articles_by_feed = Array(snapshot[:articles]).group_by(&:feed_id)
          Array(snapshot[:feeds]).sort_by { |feed| feed.title.downcase }.filter_map do |feed|
            build_feed_projection_entry(feed, articles_by_feed[feed.id], scope)
          end
        end

        def build_feed_projection_entry(feed, feed_articles, scope)
          counts = article_counts(feed_articles)
          return if hidden_by_scope?(counts, scope)

          {
            key: feed.id,
            kind: :feed,
            title: feed.title,
            url: feed.url,
            site_url: feed.site_url,
            count: scope_count(counts, scope),
            unread_count: counts[:unread],
            starred_count: counts[:starred],
            article_count: counts[:all],
            sync_error: feed.sync_error,
            last_synced_at: feed.last_synced_at,
          }
        end

        def filtered_articles(snapshot, filters, feed_titles)
          Array(snapshot[:articles])
            .select { |article| filters[:selected_feed] == all_feeds_key || article.feed_id == filters[:selected_feed] }
            .select { |article| include_article_for_scope?(article, filters[:scope]) }
            .select { |article| matches_query?(article, feed_titles[article.feed_id], filters[:query]) }
            .sort_by { |article| article_sort_tuple(article) }
        end

        def article_projection_entry(article, feed_title)
          {
            id: article.id,
            feed_id: article.feed_id,
            feed_title: feed_title.to_s,
            title: article.title,
            author: article.author,
            summary: article.summary,
            content: article.content.to_s.empty? ? article.summary : article.content,
            url: article.url,
            published_at: article.published_at,
            published_label: published_label(article.published_at),
            read: article.read,
            starred: article.starred,
          }
        end

        def feed_title_index(snapshot)
          Array(snapshot[:feeds]).to_h { |feed| [feed.id, feed.title] }
        end

        def normalized_selected_feed_key(selected_feed_key)
          selected_feed = selected_feed_key.to_s.strip
          selected_feed.empty? ? all_feeds_key : selected_feed
        end

        def projection_filters(selected_feed_key, scope, query)
          {
            selected_feed: normalized_selected_feed_key(selected_feed_key),
            scope: normalize_scope(scope),
            query: query,
          }
        end

        def article_counts(articles)
          {
            all: Array(articles).length,
            unread: Array(articles).count { |article| article.read != true },
            starred: Array(articles).count(&:starred),
          }
        end

        def scope_count(counts, scope)
          case scope
          when :unread then counts[:unread]
          when :starred then counts[:starred]
          else counts[:all]
          end
        end

        def hidden_by_scope?(counts, scope)
          return false if scope == :all

          scope_count(counts, scope).zero?
        end

        def all_feeds_entry(articles, scope)
          counts = article_counts(articles)
          {
            key: all_feeds_key,
            kind: :all,
            title: 'All Feeds',
            url: nil,
            site_url: nil,
            count: scope_count(counts, scope),
            unread_count: counts[:unread],
            starred_count: counts[:starred],
            article_count: counts[:all],
            sync_error: nil,
            last_synced_at: nil,
          }
        end

        def include_article_for_scope?(article, scope)
          case scope
          when :unread then article.read != true
          when :starred then article.starred == true
          else true
          end
        end

        def matches_query?(article, feed_title, query)
          normalized = query.to_s.strip.downcase
          return true if normalized.empty?

          haystack = [article.title, article.author, article.summary, article.content, feed_title].join("\n").downcase
          normalized.split(/\s+/).all? { |token| haystack.include?(token) }
        end

        def article_sort_tuple(article)
          [-(time_to_epoch(article.published_at) || 0), article.title.downcase]
        end

        def all_feeds_key
          self.class::ALL_FEEDS_KEY
        end
      end
    end
  end
end
