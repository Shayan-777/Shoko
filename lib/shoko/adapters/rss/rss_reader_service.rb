# frozen_string_literal: true

require 'digest'

require_relative '../../core/models/rss_article'
require_relative '../../core/models/rss_feed'
require_relative '../../shared/text_sanitizer'
require_relative '../base_adapter'
require_relative 'rss_reader_service/sanitization_support'
require_relative 'rss_reader_service/feed_support'
require_relative 'rss_reader_service/article_support'
require_relative 'rss_reader_service/content_support'
require_relative 'rss_reader_service/projection_support'
require_relative 'rss_reader_service/sync_support'

module Shoko
  module Adapters
    module Rss
      # Local-first RSS reader service that persists subscriptions and cached articles.
      class RssReaderService < Shoko::Adapters::BaseAdapter
        include RssReaderServiceSanitizationSupport
        include RssReaderServiceFeedSupport
        include RssReaderServiceArticleSupport
        include RssReaderServiceContentSupport
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
      end
    end
  end
end
