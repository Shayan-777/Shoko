# frozen_string_literal: true

require 'shoko/shared/hash_normalizer'
require 'digest'
require 'fileutils'
require 'json'

require_relative '../../core/models/rss_feed'
require_relative '../../core/models/rss_article'
require_relative 'codecs/rss_codec'
require_relative '../../shared/errors'
require_relative 'atomic_file_writer'
require_relative 'config_paths'

module Shoko
  module Adapters
    module Storage
      # File-backed persistence for RSS reader subscriptions and cached articles.
      class RssReaderRepository
        FILE_NAME = 'rss_reader.json'
        SCHEMA_VERSION = 2
        LEGACY_SCHEMA_VERSION = 1
        BODY_DIRECTORY_SUFFIX = '_articles'

        def self.default_file_path
          File.join(ConfigPaths.config_root, FILE_NAME)
        end

        def initialize(file_path:, atomic_file_writer:, file_utils: FileUtils, logger: nil)
          @file_path = file_path.to_s
          @atomic_file_writer = atomic_file_writer
          @file_utils = file_utils
          @logger = logger
          @mutex = Mutex.new
          @snapshot_cache = nil
          @body_ids = {}
          @legacy_loaded = false
          raise ArgumentError, 'file_path is required' if @file_path.strip.empty?
          raise ArgumentError, 'atomic_file_writer is required' if @atomic_file_writer.nil?
        end

        # Loading is best-effort: a corrupt or unreadable rss_reader.json must
        # degrade to an empty snapshot (config.json parity) instead of
        # permanently disabling the RSS reader. Corrupt content is quarantined
        # first, so a later save cannot overwrite the evidence.
        def load
          @mutex.synchronize { load_unlocked }
        end

        def save(feeds:, articles:)
          @mutex.synchronize { save_unlocked(feeds: feeds, articles: articles) }
        end

        # Loads the body for one article on demand. Menu snapshots stay
        # metadata-only after restart; opening an article pays for one small
        # body file instead of parsing the entire cache.
        def load_article(article_id)
          @mutex.synchronize do
            snapshot = load_unlocked
            snapshot = save_unlocked(feeds: snapshot[:feeds], articles: snapshot[:articles]) if @legacy_loaded
            article = Array(snapshot[:articles]).find { |candidate| candidate.id == article_id.to_s }
            return nil unless article
            return article unless @body_ids.include?(article.id)

            body = load_article_body(article.id)
            article.with(content: body[:content], content_blocks: body[:content_blocks])
          end
        end

        # Atomic read-modify-write: the whole load→compute→save cycle runs
        # under one lock, so a mutation on the menu thread can never be lost
        # under a concurrent worker-side merge (and vice versa). All writers
        # must go through here; the block gets the CURRENT snapshot and
        # returns the next `{ feeds:, articles: }` state.
        def update
          raise ArgumentError, 'block required' unless block_given?

          @mutex.synchronize do
            current = load_unlocked
            next_state = yield(current)
            normalized = normalize_snapshot(next_state || current)
            save_unlocked(feeds: normalized[:feeds], articles: normalized[:articles])
          end
        end

        private

        def load_unlocked
          return @snapshot_cache if @snapshot_cache
          return cache_snapshot(blank_snapshot) unless File.exist?(@file_path)

          payload = normalize_hash_keys(JSON.parse(File.read(@file_path)))
          validate_payload!(payload)
          cache_snapshot(snapshot_from_payload(payload))
        # resilient-boundary
        rescue StandardError => e
          cache_snapshot(swallow_load_error(e))
        end

        def save_unlocked(feeds:, articles:)
          normalized = normalize_snapshot(feeds: feeds, articles: articles)
          previous = load_unlocked
          snapshot = {
            schema_version: SCHEMA_VERSION,
            feeds: normalized[:feeds],
            articles: normalized[:articles],
          }
          persist_changed_bodies(previous[:articles], snapshot[:articles])
          persist_payload(serialized_snapshot(feeds: snapshot[:feeds], articles: snapshot[:articles]))
          @legacy_loaded = false
          cache_snapshot(snapshot)
        rescue StandardError => e
          raise_storage_error('rss_reader_save', e)
        end

        def blank_snapshot
          {
            schema_version: SCHEMA_VERSION,
            feeds: [],
            articles: [],
          }
        end

        def validate_payload!(payload)
          unless payload.is_a?(Hash)
            raise Shoko::StorageError.new('rss_reader_load', @file_path, 'expected a hash payload')
          end

          version = payload[:schema_version].to_i
          @legacy_loaded = version == LEGACY_SCHEMA_VERSION
          unless [LEGACY_SCHEMA_VERSION, SCHEMA_VERSION].include?(version)
            raise Shoko::StorageError.new('rss_reader_load', @file_path,
                                          "unsupported schema_version #{version.inspect}")
          end

          %i[feeds articles].each do |key|
            value = payload[key]
            next if value.is_a?(Array)

            raise Shoko::StorageError.new('rss_reader_load', @file_path, "#{key} must be an array")
          end
        end

        def snapshot_from_payload(payload)
          version = payload[:schema_version].to_i
          rows = Array(payload[:articles])
          @body_ids = body_ids_from(rows, version)
          {
            schema_version: SCHEMA_VERSION,
            feeds: Array(payload[:feeds]).map { |row| Codecs::RssCodec.load_feed(row) },
            articles: rows.map do |row|
              Codecs::RssCodec.load_article(article_payload(row, version))
            end,
          }
        end

        def article_payload(row, version)
          normalized = normalize_hash_keys(row)
          return normalized if version == LEGACY_SCHEMA_VERSION

          normalized.merge(content: '', content_blocks: [])
        end

        def body_ids_from(rows, version)
          Array(rows).each_with_object({}) do |row, ids|
            normalized = normalize_hash_keys(row)
            has_body = if version == LEGACY_SCHEMA_VERSION
                         !normalized[:content].to_s.empty? || !Array(normalized[:content_blocks]).empty?
                       else
                         normalized[:has_body] == true
                       end
            ids[normalized[:id].to_s] = true if has_body
          end
        end

        def load_article_body(article_id)
          path = article_body_path(article_id)
          return { content: '', content_blocks: [] } unless File.exist?(path)

          payload = normalize_hash_keys(JSON.parse(File.read(path)))
          Codecs::RssCodec.load_body(payload)
        # resilient-boundary
        rescue StandardError => e
          record_article_body_load_error(e, path)
        end

        def record_article_body_load_error(error, path)
          @logger&.warn('rss_reader.article_body_load_degraded',
                        path: path, error_class: error.class.name, error: error.message)
          { content: '', content_blocks: [] }
        end

        def normalize_snapshot(snapshot)
          raise ArgumentError, "rss reader snapshot must be a Hash, got #{snapshot.class}" unless snapshot.is_a?(Hash)

          normalized = normalize_hash_keys(snapshot)

          {
            feeds: Array(normalized[:feeds]).map { |feed| coerce_feed(feed) },
            articles: Array(normalized[:articles]).map { |article| coerce_article(article) },
          }
        end

        def coerce_feed(feed)
          return feed if feed.is_a?(Shoko::Core::Models::RssFeed)

          Codecs::RssCodec.load_feed(feed)
        end

        def coerce_article(article)
          return article if article.is_a?(Shoko::Core::Models::RssArticle)

          Codecs::RssCodec.load_article(article)
        end

        def raise_storage_error(operation, error)
          raise error if error.is_a?(Shoko::Error)

          raise Shoko::StorageError.new(operation, @file_path, error.message)
        end

        # The failures here (JSON::ParserError, validation StorageError,
        # Errno::*) are not recoverable by the caller; the boundary degrades
        # to a blank snapshot. Only bad CONTENT is quarantined — an unreadable
        # file (permissions, transient IO) is left in place.
        def swallow_load_error(error)
          quarantine_corrupt_file if content_error?(error)
          @logger&.warn('rss_reader.load_degraded',
                        path: @file_path, error_class: error.class.name, error: error.message)
          blank_snapshot
        end

        def content_error?(error)
          error.is_a?(JSON::ParserError) || error.is_a?(Shoko::StorageError)
        end

        def quarantine_corrupt_file
          timestamp = Time.now.utc.strftime('%Y%m%d%H%M%S')
          quarantine_path = "#{@file_path}.corrupt-#{timestamp}"
          File.rename(@file_path, quarantine_path)
          @logger&.warn('rss_reader.corrupt_file_quarantined', from: @file_path, to: quarantine_path)
        # resilient-boundary
        rescue StandardError => e
          record_quarantine_error(e)
        end

        def record_quarantine_error(error)
          @logger&.warn('rss_reader.quarantine_failed',
                        path: @file_path, error_class: error.class.name, error: error.message)
        end

        def normalize_hash_keys(payload)
          Shoko::Shared::HashNormalizer.symbolize_keys(payload) || payload
        end

        def serialized_snapshot(feeds:, articles:)
          {
            schema_version: SCHEMA_VERSION,
            feeds: Array(feeds).map { |feed| Codecs::RssCodec.dump_feed(coerce_feed(feed)) },
            articles: Array(articles).map { |article| serialized_article_metadata(coerce_article(article)) },
          }
        end

        def serialized_article_metadata(article)
          Codecs::RssCodec.dump_article(article)
                          .except(:content, :content_blocks)
                          .merge(has_body: article_body?(article) || @body_ids.include?(article.id))
        end

        def persist_changed_bodies(previous_articles, articles)
          previous_by_id = Array(previous_articles).to_h { |article| [article.id, article] }
          Array(articles).each { |article| persist_article_body(article, previous_by_id[article.id]) }
        end

        def persist_article_body(article, previous)
          return unless article_body?(article)

          path = article_body_path(article.id)
          return if previous && same_article_body?(previous, article) && File.exist?(path)

          @file_utils.mkdir_p(File.dirname(path))
          @atomic_file_writer.write(
            path,
            JSON.generate(Codecs::RssCodec.dump_body(article))
          )
          @body_ids[article.id] = true
        end

        def article_body?(article)
          !article.content.to_s.empty? || !Array(article.content_blocks).empty?
        end

        def same_article_body?(left, right)
          left.content == right.content && left.content_blocks == right.content_blocks
        end

        def article_body_path(article_id)
          digest = Digest::SHA256.hexdigest(article_id.to_s)
          File.join(article_body_directory, "#{digest}.json")
        end

        def article_body_directory
          stem = File.basename(@file_path, File.extname(@file_path))
          File.join(File.dirname(@file_path), "#{stem}#{BODY_DIRECTORY_SUFFIX}")
        end

        def persist_payload(payload)
          @file_utils.mkdir_p(File.dirname(@file_path))
          @atomic_file_writer.write(@file_path, JSON.pretty_generate(payload))
        end

        def cache_snapshot(snapshot)
          @snapshot_cache = snapshot
        end
      end
    end
  end
end
