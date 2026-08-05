# frozen_string_literal: true

require 'time'

module Shoko
  module Adapters
    module Rss
      # Builds stable menu and reader projections from persisted RSS records.
      class RssProjection
        def initialize(all_feeds_key:)
          @all_feeds_key = all_feeds_key
        end

        def feeds(snapshot:, scope:)
          scope = normalize_scope(scope)
          [all_feeds_entry(snapshot[:articles], scope), *visible_feeds(snapshot, scope)]
        end

        def articles(snapshot:, selected_feed_key:, scope:, query:)
          criteria = filters(selected_feed_key, scope, query)
          titles = feed_title_index(snapshot)
          filtered_articles(snapshot, criteria, titles).map do |article|
            article_entry(article, titles[article.feed_id])
          end
        end

        def reader_entry(article, snapshot)
          article_entry(article, feed_title_index(snapshot)[article.feed_id]).merge(
            content: article.content.to_s.empty? ? article.summary : article.content,
            content_blocks: article.content_blocks
          )
        end

        def normalize_feed_key(feeds:, preferred_key:)
          keys = Array(feeds).map { |feed| feed[:key].to_s }
          preferred = preferred_key.to_s.strip
          return @all_feeds_key if keys.empty?
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

        def last_synced_at(snapshot) = Array(snapshot[:feeds]).filter_map(&:last_synced_at).max
        def sort_tuple(article) = [-(time_to_epoch(article.published_at) || 0), article.title.downcase]

        private

        def normalize_scope(scope)
          return :unread if scope&.to_sym == :unread
          return :starred if scope&.to_sym == :starred

          :all
        end

        def visible_feeds(snapshot, scope)
          grouped = Array(snapshot[:articles]).group_by(&:feed_id)
          Array(snapshot[:feeds]).sort_by { |feed| feed.title.downcase }.filter_map do |feed|
            feed_entry(feed, grouped[feed.id], scope)
          end
        end

        def feed_entry(feed, articles, scope)
          counts = article_counts(articles)
          return if scope != :all && scope_count(counts, scope).zero?

          { key: feed.id, kind: :feed, title: feed.title, url: feed.url, site_url: feed.site_url,
            count: scope_count(counts, scope), unread_count: counts[:unread], starred_count: counts[:starred],
            article_count: counts[:all], sync_error: feed.sync_error, last_synced_at: feed.last_synced_at }
        end

        def all_feeds_entry(articles, scope)
          counts = article_counts(articles)
          { key: @all_feeds_key, kind: :all, title: 'All Feeds', url: nil, site_url: nil,
            count: scope_count(counts, scope), unread_count: counts[:unread], starred_count: counts[:starred],
            article_count: counts[:all], sync_error: nil, last_synced_at: nil }
        end

        def filtered_articles(snapshot, criteria, titles)
          Array(snapshot[:articles])
            .select { |article| criteria[:feed] == @all_feeds_key || article.feed_id == criteria[:feed] }
            .select { |article| in_scope?(article, criteria[:scope]) }
            .select { |article| matches?(article, titles[article.feed_id], criteria[:query]) }
            .sort_by { |article| sort_tuple(article) }
        end

        def article_entry(article, feed_title)
          { id: article.id, feed_id: article.feed_id, feed_title: feed_title.to_s, title: article.title,
            author: article.author, summary: article.summary, url: article.url,
            published_at: article.published_at, published_label: published_label(article.published_at),
            read: article.read, starred: article.starred }
        end

        def filters(selected_feed_key, scope, query)
          selected = selected_feed_key.to_s.strip
          { feed: selected.empty? ? @all_feeds_key : selected, scope: normalize_scope(scope), query: query }
        end

        def feed_title_index(snapshot) = Array(snapshot[:feeds]).to_h { |feed| [feed.id, feed.title] }

        def article_counts(articles)
          { all: Array(articles).length, unread: Array(articles).count { |article| article.read != true },
            starred: Array(articles).count(&:starred) }
        end

        def scope_count(counts, scope)
          return counts[:unread] if scope == :unread
          return counts[:starred] if scope == :starred

          counts[:all]
        end

        def in_scope?(article, scope)
          return article.read != true if scope == :unread
          return article.starred == true if scope == :starred

          true
        end

        def matches?(article, feed_title, query)
          normalized = query.to_s.strip.downcase
          return true if normalized.empty?

          haystack = [article.title, article.author, article.summary, article.content, feed_title].join("\n").downcase
          normalized.split(/\s+/).all? { |token| haystack.include?(token) }
        end

        def published_label(value)
          parsed = parsed_time(value)
          parsed ? parsed.localtime.strftime('%Y-%m-%d %H:%M') : 'Unknown date'
        end

        def time_to_epoch(value) = parsed_time(value)&.to_i

        def parsed_time(value)
          text = value.to_s.strip
          text.empty? ? nil : Time.parse(text)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
