# frozen_string_literal: true

require 'digest'

require_relative '../../core/models/rss_article'
require_relative '../../core/models/rss_feed'
require_relative '../../shared/text_sanitizer'
require_relative '../base_adapter'
require_relative 'rss_reader_service/sanitization_support'
require_relative 'rss_reader_service/feed_support'
require_relative 'rss_reader_service/projection_support'
require_relative 'rss_reader_service/sync_support'

module Shoko
  module Adapters
    module Rss
      # Local-first RSS reader service that persists subscriptions and cached articles.
      class RssReaderService < Shoko::Adapters::BaseAdapter
        include RssReaderServiceSanitizationSupport
        include RssReaderServiceFeedSupport
        include RssReaderServiceProjectionSupport
        include RssReaderServiceSyncSupport

        ALL_FEEDS_KEY = '__all__'
        MAX_ARTICLES_PER_FEED = 250
        MAX_SUMMARY_LENGTH = 1600
        MAX_CONTENT_LENGTH = 12_000
        MAX_TITLE_LENGTH = 220
        MAX_AUTHOR_LENGTH = 120
        MAX_ERROR_LENGTH = 160
        FULL_CONTENT_MIN_LENGTH = 1000
        FULL_CONTENT_GAIN_THRESHOLD = 200

        def initialize(repository:, feed_fetcher:, wall_clock:, article_content_fetcher: nil, text_sanitizer: nil,
                       logger: nil)
          super(logger: logger)
          raise ArgumentError, 'repository is required' if repository.nil?
          raise ArgumentError, 'feed_fetcher is required' if feed_fetcher.nil?
          raise ArgumentError, 'wall_clock must respond to #utc_now' unless wall_clock.respond_to?(:utc_now)

          @repository = repository
          @feed_fetcher = feed_fetcher
          @wall_clock = wall_clock
          @article_content_fetcher = article_content_fetcher
          @text_sanitizer = text_sanitizer
        end

        def snapshot
          @repository.load
        end

        def remove_feed(feed_id)
          target_feed_id = feed_id.to_s
          current = snapshot
          remaining_feeds = current[:feeds].reject { |feed| feed.id == target_feed_id }
          remaining_articles = current[:articles].reject { |article| article.feed_id == target_feed_id }
          @repository.save(feeds: remaining_feeds, articles: remaining_articles)
        end

        def set_article_read(article_id, read:)
          update_article(article_id) { |article| article.with(read: read == true) }
        end

        def set_article_starred(article_id, starred:)
          update_article(article_id) { |article| article.with(starred: starred == true) }
        end

        private

        def update_article(article_id)
          current = snapshot
          target_id = article_id.to_s
          updated = Array(current[:articles]).map do |article|
            article.id == target_id ? yield(article) : article
          end
          @repository.save(feeds: current[:feeds], articles: updated)
        end

        # Article merge, retention, and record-building helpers for RSS reader sync.
        def merge_feed_articles(existing_articles, parsed_articles, feed_id_value)
          refreshed = refreshed_articles(existing_articles, parsed_articles, feed_id_value)
          merged = refreshed + retained_existing_articles(existing_articles, refreshed)
          retained_articles(merged).sort_by { |article| article_sort_tuple(article) }
        end

        def build_article_record(feed_id_value, payload, existing_index)
          title = sanitized_article_title(payload)
          return nil unless title

          article_id_value = article_id(feed_id_value, payload)
          existing = existing_index[article_id_value]
          summary = sanitized_article_summary(payload)
          content = sanitized_article_content(payload, summary)
          article_data = {
            id: article_id_value,
            title: title,
            summary: summary,
            content: content,
          }

          Shoko::Core::Models::RssArticle.new(
            **article_record_attributes(feed_id_value, payload, existing, article_data)
          )
        end

        def replace_feed_articles(all_articles, feed_id_value, replacement)
          Array(all_articles).reject { |article| article.feed_id == feed_id_value } + Array(replacement)
        end

        def article_id(feed_id_value, payload)
          basis = [feed_id_value.to_s, article_identity(payload)].join('|')
          Digest::SHA256.hexdigest(basis)
        end

        def refreshed_articles(existing_articles, parsed_articles, feed_id_value)
          existing_index = index_articles(existing_articles)
          Array(parsed_articles).filter_map do |payload|
            build_article_record(feed_id_value, payload, existing_index)
          end
        end

        def retained_existing_articles(existing_articles, refreshed_articles)
          refreshed_ids = refreshed_articles.map(&:id)
          Array(existing_articles).reject { |article| refreshed_ids.include?(article.id) }
        end

        def retained_articles(articles)
          preserve, remainder = Array(articles).partition { |article| article.starred || !article.read }
          preserve + remainder.first(retained_remainder_limit(preserve.length))
        end

        def retained_remainder_limit(preserve_length)
          [self.class::MAX_ARTICLES_PER_FEED - preserve_length, 0].max
        end

        def index_articles(articles)
          Array(articles).to_h { |article| [article.id, article] }
        end

        def article_record_attributes(feed_id_value, payload, existing, article_data)
          {
            id: article_data[:id],
            feed_id: feed_id_value,
            title: article_data[:title],
            summary: article_data[:summary],
            content: article_data[:content],
            published_at: sanitize_time(payload[:published_at]) || existing&.published_at || timestamp,
            fetched_at: timestamp,
          }.merge(article_text_attributes(payload)).merge(article_state_attributes(existing))
        end

        def sanitized_article_title(payload)
          title = sanitize_text(payload[:title], preserve_newlines: false, max_length: self.class::MAX_TITLE_LENGTH)
          return nil if title.to_s.strip.empty?

          title
        end

        def sanitized_article_summary(payload)
          sanitize_text(payload[:summary], preserve_newlines: true, max_length: self.class::MAX_SUMMARY_LENGTH)
        end

        def sanitized_article_content(payload, summary)
          content_source = payload[:content].to_s.strip.empty? ? summary : payload[:content]
          sanitize_text(content_source, preserve_newlines: true, max_length: self.class::MAX_CONTENT_LENGTH)
        end

        def article_identity(payload)
          guid = payload[:guid].to_s.strip
          return "guid:#{guid}" unless guid.empty?

          url = payload[:url].to_s.strip
          return "url:#{url}" unless url.empty?

          [
            "title:#{payload[:title].to_s.strip}",
            "published:#{sanitize_time(payload[:published_at])}",
          ].join('|')
        end

        def article_text_attributes(payload)
          {
            guid: sanitize_text(payload[:guid], max_length: 600),
            author: sanitize_text(
              payload[:author],
              preserve_newlines: false,
              max_length: self.class::MAX_AUTHOR_LENGTH
            ),
            url: sanitize_text(payload[:url], preserve_newlines: false, max_length: 600),
          }
        end

        def article_state_attributes(existing)
          {
            read: existing&.read == true,
            starred: existing&.starred == true,
          }
        end

        # Full-article hydration helpers for the RSS reader service.
        def hydrate_article_payloads(parsed_articles)
          Array(parsed_articles).map { |payload| hydrate_article_payload(payload) }
        end

        def hydrate_article_payload(payload)
          article = payload.dup
          return article unless should_fetch_full_content?(article)

          full_content = @article_content_fetcher.fetch(article[:url])
          return article unless full_content_more_complete?(article, full_content)

          article.merge(
            content: full_content,
            summary: derive_summary(article[:summary], full_content)
          )
        rescue ArticleContentFetcher::FetchError => e
          log_debug('rss_reader.article_content_fetch_failed', url: article[:url], error: e.message)
          article
        end

        def should_fetch_full_content?(payload)
          return false unless @article_content_fetcher

          url = payload[:url].to_s.strip
          return false if url.empty?

          content = payload[:content].to_s.strip
          summary = payload[:summary].to_s.strip
          content.empty? || truncated_content?(content, summary)
        end

        def truncated_content?(content, summary)
          content.length < self.class::FULL_CONTENT_MIN_LENGTH &&
            content.length <= summary.length + self.class::FULL_CONTENT_GAIN_THRESHOLD
        end

        def full_content_more_complete?(payload, full_content)
          current = payload[:content].to_s.strip
          fetched = full_content.to_s.strip
          return false if fetched.empty?

          current.empty? || fetched.length > current.length + self.class::FULL_CONTENT_GAIN_THRESHOLD
        end

        def derive_summary(current_summary, full_content)
          summary = current_summary.to_s.strip
          return summary unless summary.empty?

          excerpt_from(full_content)
        end
      end
    end
  end
end
