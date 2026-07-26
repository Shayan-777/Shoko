# frozen_string_literal: true

require 'digest'
require_relative 'article_block_sanitizer'
require 'shoko/core/models/content_block_payload'

require_relative '../../core/models/rss_article'
require_relative '../../core/models/rss_feed'
require_relative '../../shared/text_sanitizer'
require_relative '../base_adapter'
require 'uri'
require 'time'

module Shoko
  module Adapters
    module Rss
      # Local-first RSS reader service that persists subscriptions and cached articles.
      class RssReaderService < Shoko::Adapters::BaseAdapter
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
          @block_sanitizer = ArticleBlockSanitizer.new(max_text_length: self.class::MAX_CONTENT_LENGTH)
        end

        def snapshot
          @repository.load
        end

        def remove_feed(feed_id)
          target_feed_id = feed_id.to_s
          @repository.update do |current|
            {
              feeds: current[:feeds].reject { |feed| feed.id == target_feed_id },
              articles: current[:articles].reject { |article| article.feed_id == target_feed_id },
            }
          end
        end

        def set_article_read(article_id, read:)
          update_article(article_id) { |article| article.with(read: read == true) }
        end

        def set_article_starred(article_id, starred:)
          update_article(article_id) { |article| article.with(starred: starred == true) }
        end

        # Feed/article projection helpers used by the menu-side RSS reader workflow.
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

        # Feed subscription and sync orchestration for the RSS reader service.
        #
        # Both run in two phases: all network work first (unlocked, off the
        # repository), then one atomic `repository.update` merge against the
        # snapshot as it is THEN — so nothing the user changed while the
        # fetches ran (read/star flags, removed feeds) is lost to a stale
        # read-modify-write.
        def add_feed(url)
          fetched = fetched_feed_payload(url)
          feed = build_feed_record(url: fetched[:url], fetched: fetched)
          article_payloads = hydrate_article_payloads(fetched[:articles])

          added_count = 0
          merged = @repository.update do |current|
            ensure_feed_not_subscribed!(current[:feeds], fetched[:url])
            articles = merge_feed_articles([], article_payloads, feed.id)
            added_count = articles.length
            { feeds: current[:feeds] + [feed], articles: current[:articles] + articles }
          end

          { snapshot: merged, feed_key: feed.id, added_count: added_count }
        end

        def sync_all
          current = snapshot
          return empty_sync_result(current) if Array(current[:feeds]).empty?

          merge_sync_results(current[:feeds].map { |feed| fetch_feed_result(feed) })
        end

        private

        def update_article(article_id)
          target_id = article_id.to_s
          @repository.update do |current|
            updated = Array(current[:articles]).map do |article|
              article.id == target_id ? yield(article) : article
            end
            { feeds: current[:feeds], articles: updated }
          end
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
          Shoko::Core::Models::RssArticle.new(
            **article_record_attributes(
              feed_id_value, payload, existing_index[article_id_value],
              sanitized_article_data(article_id_value, title, payload)
            )
          )
        end

        def sanitized_article_data(article_id_value, title, payload)
          summary = sanitized_article_summary(payload)
          {
            id: article_id_value,
            title: title,
            summary: summary,
            content: sanitized_article_content(payload, summary),
            content_blocks: sanitized_article_blocks(payload),
          }
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
            content_blocks: article_data[:content_blocks],
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

        # Blocks arrive as ContentBlocks from the parser (or as stored payloads
        # when an article round-trips); both are sanitized, bounded, and stored
        # in the plain wire shape.
        def sanitized_article_blocks(payload)
          blocks = payload[:content_blocks]
          return [] if blocks.nil? || Array(blocks).empty?

          parsed = Array(blocks).first.is_a?(Shoko::Core::Models::ContentBlock) ? blocks : blocks_from_payload(blocks)
          Shoko::Core::Models::ContentBlockPayload.dump(@block_sanitizer.call(parsed))
        end

        def blocks_from_payload(blocks)
          Shoko::Core::Models::ContentBlockPayload.load(blocks)
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

          fetched = @article_content_fetcher.fetch(article[:url])
          return article unless full_content_more_complete?(article, fetched.text)

          article.merge(
            content: fetched.text,
            content_blocks: fetched.blocks,
            summary: derive_summary(article[:summary], fetched.text)
          )
        # Resilient boundary (R4): full-article hydration is a best-effort
        # enrichment that runs arbitrary third-party HTML through the fetcher,
        # the extractor, and the entity decoder. The error set there is
        # unbounded — malformed markup, mislabelled encodings, and plain bugs
        # are not Shoko errors — and a single unreadable article must never
        # abort subscribing to the feed. The article keeps its feed-supplied
        # summary and the subscription proceeds.
        # resilient-boundary
        rescue StandardError => e
          record_article_hydration_error(article, e)
          article
        end

        def record_article_hydration_error(article, error)
          log_debug(
            'rss_reader.article_content_fetch_failed',
            url: article[:url],
            error_class: error.class.name,
            error: error.message
          )
          nil
        end

        def should_fetch_full_content?(payload)
          return false unless @article_content_fetcher

          url = payload[:url].to_s.strip
          return false if url.empty?

          existing = best_existing_text(payload)
          existing.empty? || truncated_content?(existing, payload[:summary].to_s.strip)
        end

        # The richest text the feed already handed us: a dedicated content element when
        # present, otherwise the description/summary (many feeds ship the full article
        # body there and never populate content:encoded).
        def best_existing_text(payload)
          content = payload[:content].to_s.strip
          content.empty? ? payload[:summary].to_s.strip : content
        end

        def truncated_content?(content, summary)
          content.length < self.class::FULL_CONTENT_MIN_LENGTH &&
            content.length <= summary.length + self.class::FULL_CONTENT_GAIN_THRESHOLD
        end

        def full_content_more_complete?(payload, full_content)
          fetched = full_content.to_s.strip
          return false if fetched.empty?

          existing = best_existing_text(payload)
          return fetched.length > existing.length if payload[:content].to_s.strip.empty?

          fetched.length > existing.length + self.class::FULL_CONTENT_GAIN_THRESHOLD
        end

        def derive_summary(current_summary, full_content)
          summary = current_summary.to_s.strip
          return summary unless summary.empty?

          excerpt_from(full_content)
        end

        # Feed record builders and feed identity helpers for the RSS reader service.
        def build_feed_record(url:, fetched:)
          Shoko::Core::Models::RssFeed.new(**feed_record_attributes(url, fetched))
        end

        def refresh_feed_record(feed, fetched)
          feed.with(**refreshed_feed_attributes(feed, fetched))
        end

        def not_modified_feed_record(feed, fetched)
          feed.with(
            etag: fetched[:etag] || feed.etag,
            last_modified: fetched[:last_modified] || feed.last_modified,
            sync_error: nil,
            last_synced_at: timestamp
          )
        end

        def feed_record_attributes(url, fetched)
          {
            id: feed_id(url),
            url: url,
            title: feed_title(fetched[:title], url),
            site_url: sanitize_text(fetched[:site_url], max_length: 600),
            etag: sanitize_text(fetched[:etag], max_length: 200),
            last_modified: sanitize_text(fetched[:last_modified], max_length: 200),
            added_at: timestamp,
            last_synced_at: timestamp,
            sync_error: nil,
          }
        end

        def refreshed_feed_attributes(feed, fetched)
          {
            title: feed_title(fetched[:title], feed.url),
            site_url: sanitize_text(fetched[:site_url], max_length: 600) || feed.site_url,
            etag: sanitize_text(fetched[:etag], max_length: 200),
            last_modified: sanitize_text(fetched[:last_modified], max_length: 200),
            last_synced_at: timestamp,
            sync_error: nil,
          }
        end

        def feed_id(url)
          Digest::SHA256.hexdigest(url.to_s.strip)
        end

        def feed_title(raw_title, url)
          title = sanitize_text(raw_title, preserve_newlines: false, max_length: self.class::MAX_TITLE_LENGTH)
          return title unless title.to_s.strip.empty?

          URI.parse(url.to_s).host.to_s.tap { |host| return host unless host.empty? }
          'Untitled Feed'
        rescue URI::InvalidURIError
          'Untitled Feed'
        end

        # Shared text and time normalization helpers for RSS reader records.
        def sanitize_text(text, preserve_newlines: false, max_length: nil)
          sanitized = if @text_sanitizer
                        @text_sanitizer.sanitize(
                          text.to_s,
                          preserve_newlines: preserve_newlines,
                          max_length: max_length
                        )
                      else
                        sanitize_text_default(text, preserve_newlines: preserve_newlines, max_length: max_length)
                      end
          value = sanitized.to_s.strip
          return nil if value.empty?

          value
        end

        def sanitize_text_default(text, preserve_newlines:, max_length:)
          value = Shoko::Shared::TextSanitizer.sanitize(
            text.to_s,
            preserve_newlines: preserve_newlines,
            preserve_tabs: false
          )
          max_length ? value[0, max_length] : value
        end

        def sanitize_time(value)
          parsed_time(value)&.utc&.iso8601
        end

        def time_to_epoch(value)
          parsed_time(value)&.to_i
        end

        def published_label(value)
          parsed = parsed_time(value)
          return 'Unknown date' unless parsed

          parsed.localtime.strftime('%Y-%m-%d %H:%M')
        end

        def normalize_scope(scope)
          case scope&.to_sym
          when :unread then :unread
          when :starred then :starred
          else :all
          end
        end

        def timestamp
          @wall_clock.utc_now.iso8601
        end

        def excerpt_from(text)
          excerpt = text.to_s.strip.gsub(/\s+/, ' ')[0, 320].to_s.strip
          return nil if excerpt.empty?

          excerpt
        end

        def parsed_time(value)
          text = value.to_s.strip
          return nil if text.empty?

          Time.parse(text)
        rescue ArgumentError
          invalid_parsed_time
        end

        def invalid_parsed_time
          nil
        end

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
            content_blocks: article.content_blocks,
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

        # Network phase: fetch (and hydrate) one feed with no repository
        # access, so the repository lock is never held across a fetch.
        def fetch_feed_result(feed)
          fetched = @feed_fetcher.fetch(feed.url, etag: feed.etag, last_modified: feed.last_modified)
          return { feed_id: feed.id, status: :not_modified, fetched: fetched } if fetched[:not_modified]

          {
            feed_id: feed.id,
            status: :synced,
            fetched: fetched,
            article_payloads: hydrate_article_payloads(fetched[:articles]),
          }
        rescue FeedFetcher::FetchError, FeedParser::ParseError => e
          { feed_id: feed.id, status: :error, error: e }
        end

        # Merge phase: one atomic update against the snapshot as it is NOW.
        # Feeds removed while the fetches ran stay removed (only feeds still
        # present are merged), and read/star flags set meanwhile survive
        # because articles merge against the current state, not the pre-sync
        # one.
        def merge_sync_results(fetch_results)
          results_by_feed = fetch_results.to_h { |result| [result[:feed_id], result] }
          stats = { updated: 0, added: 0, errors: [] }

          merged = @repository.update do |current|
            merged_sync_state(current, results_by_feed, stats)
          end

          sync_result(
            feeds: merged[:feeds], articles: merged[:articles],
            checked: fetch_results.length, updated: stats[:updated],
            added: stats[:added], errors: stats[:errors]
          )
        end

        def merged_sync_state(current, results_by_feed, stats)
          next_feeds = []
          next_articles = current[:articles]
          Array(current[:feeds]).each do |feed|
            applied = apply_fetch_result(feed, results_by_feed[feed.id], next_articles, stats)
            next_feeds << applied[:feed]
            next_articles = applied[:articles]
          end
          { feeds: next_feeds, articles: next_articles }
        end

        def apply_fetch_result(feed, result, all_articles, stats)
          case result&.fetch(:status, nil)
          when :not_modified
            { feed: not_modified_feed_record(feed, result[:fetched]), articles: all_articles }
          when :synced
            apply_synced_result(feed, result, all_articles, stats)
          when :error
            { feed: feed_with_sync_error(feed, result[:error], stats), articles: all_articles }
          else
            { feed: feed, articles: all_articles }
          end
        end

        def apply_synced_result(feed, result, all_articles, stats)
          existing = feed_articles(all_articles, feed.id)
          merged_articles = merge_feed_articles(existing, result[:article_payloads], feed.id)
          stats[:added] += added_article_count(existing, merged_articles)
          stats[:updated] += 1
          {
            feed: refresh_feed_record(feed, result[:fetched]),
            articles: replace_feed_articles(all_articles, feed.id, merged_articles),
          }
        end

        def feed_articles(articles, feed_id)
          Array(articles).select { |article| article.feed_id == feed_id }
        end

        def added_article_count(existing_articles, merged_articles)
          existing_ids = Array(existing_articles).map(&:id)
          Array(merged_articles).count { |article| !existing_ids.include?(article.id) }
        end

        def feed_with_sync_error(feed, error, stats)
          message = sanitize_text(error.message, max_length: self.class::MAX_ERROR_LENGTH)
          stats[:errors] << { feed_id: feed.id, message: message }
          feed.with(sync_error: message)
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
