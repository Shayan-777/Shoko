# frozen_string_literal: true

module Shoko
  module Adapters
    module Rss
      # Feed subscription and sync orchestration for the RSS reader service.
      module RssReaderServiceSyncSupport
        def add_feed(url)
          current = snapshot
          fetched = fetched_feed_payload(url)
          ensure_feed_not_subscribed!(current[:feeds], fetched[:url])

          feed = build_feed_record(url: fetched[:url], fetched: fetched)
          articles = merge_feed_articles([], hydrate_article_payloads(fetched[:articles]), feed.id)
          @repository.save(feeds: current[:feeds] + [feed], articles: current[:articles] + articles)

          { snapshot: snapshot, feed_key: feed.id, added_count: articles.length }
        end

        def sync_all
          current = snapshot
          return empty_sync_result(current) if Array(current[:feeds]).empty?

          state = initial_sync_state(current)
          state[:feeds].each { |feed| sync_feed(feed, state) }
          persist_sync_state(state)
        end

        private

        def fetched_feed_payload(url)
          fetched = @feed_fetcher.fetch(url)
          feed_url = fetched[:url].to_s
          raise FeedFetcher::FetchError, 'Feed URL is required' if feed_url.strip.empty?

          fetched.merge(url: feed_url)
        end

        def ensure_feed_not_subscribed!(feeds, feed_url)
          duplicate = Array(feeds).any? { |feed| feed.url == feed_url || feed.id == feed_id(feed_url) }
          raise FeedFetcher::FetchError, 'Feed is already subscribed' if duplicate
        end

        def empty_sync_result(snapshot)
          sync_result(
            feeds: snapshot[:feeds],
            articles: snapshot[:articles],
            checked: 0,
            updated: 0,
            added: 0,
            errors: []
          )
        end

        def initial_sync_state(current)
          {
            feeds: Array(current[:feeds]),
            updated_feeds: [],
            updated_articles: current[:articles],
            added_count: 0,
            updated_count: 0,
            errors: [],
          }
        end

        def sync_feed(feed, state)
          feed_articles = feed_articles(state[:updated_articles], feed.id)
          fetched = @feed_fetcher.fetch(feed.url, etag: feed.etag, last_modified: feed.last_modified)
          return apply_not_modified_feed(feed, fetched, state) if fetched[:not_modified]

          apply_synced_feed(feed, feed_articles, fetched, state)
        rescue FeedFetcher::FetchError, FeedParser::ParseError => e
          apply_sync_error(feed, e, state)
        end

        def apply_not_modified_feed(feed, fetched, state)
          state[:updated_feeds] << not_modified_feed_record(feed, fetched)
        end

        def apply_synced_feed(feed, feed_articles, fetched, state)
          merged_articles = merge_feed_articles(feed_articles, hydrate_article_payloads(fetched[:articles]), feed.id)
          state[:added_count] += added_article_count(feed_articles, merged_articles)
          state[:updated_count] += 1
          state[:updated_feeds] << refresh_feed_record(feed, fetched)
          state[:updated_articles] = replace_feed_articles(state[:updated_articles], feed.id, merged_articles)
        end

        def feed_articles(articles, feed_id)
          Array(articles).select { |article| article.feed_id == feed_id }
        end

        def added_article_count(existing_articles, merged_articles)
          existing_ids = Array(existing_articles).map(&:id)
          Array(merged_articles).count { |article| !existing_ids.include?(article.id) }
        end

        def apply_sync_error(feed, error, state)
          message = sanitize_text(error.message, max_length: self.class::MAX_ERROR_LENGTH)
          state[:errors] << { feed_id: feed.id, message: message }
          state[:updated_feeds] << feed.with(sync_error: message)
        end

        def persist_sync_state(state)
          @repository.save(feeds: state[:updated_feeds], articles: state[:updated_articles])
          sync_result(
            feeds: state[:updated_feeds],
            articles: state[:updated_articles],
            checked: state[:feeds].length,
            updated: state[:updated_count],
            added: state[:added_count],
            errors: state[:errors]
          )
        end

        def sync_result(feeds:, articles:, checked:, updated:, added:, errors:)
          {
            snapshot: {
              schema_version: 1,
              feeds: feeds,
              articles: articles,
            },
            checked: checked,
            updated: updated,
            added: added,
            errors: errors,
          }
        end
      end
    end
  end
end
