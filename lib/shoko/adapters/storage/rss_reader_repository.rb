# frozen_string_literal: true

require 'fileutils'
require 'json'

require_relative '../../core/models/rss_feed'
require_relative '../../core/models/rss_article'
require_relative '../../shared/errors'
require_relative 'atomic_file_writer'
require_relative 'config_paths'

module Shoko
  module Adapters
    module Storage
      # File-backed persistence for RSS reader subscriptions and cached articles.
      class RssReaderRepository
        FILE_NAME = 'rss_reader.json'
        SCHEMA_VERSION = 1

        def self.default_file_path
          File.join(ConfigPaths.config_root, FILE_NAME)
        end

        def initialize(file_path:, atomic_file_writer:, file_utils: FileUtils)
          @file_path = file_path.to_s
          @atomic_file_writer = atomic_file_writer
          @file_utils = file_utils
          raise ArgumentError, 'file_path is required' if @file_path.strip.empty?
          raise ArgumentError, 'atomic_file_writer is required' if @atomic_file_writer.nil?
        end

        def load
          return blank_snapshot unless File.exist?(@file_path)

          payload = normalize_hash_keys(JSON.parse(File.read(@file_path)))
          validate_payload!(payload)
          snapshot_from_payload(payload)
        rescue StandardError => e
          raise_storage_error('rss_reader_load', e)
        end

        def save(feeds:, articles:)
          payload = serialized_snapshot(feeds: feeds, articles: articles)
          persist_payload(payload)
          snapshot_from_payload(payload)
        rescue StandardError => e
          raise_storage_error('rss_reader_save', e)
        end

        def update
          raise ArgumentError, 'block required' unless block_given?

          current = load
          next_state = yield(current)
          normalized = normalize_snapshot(next_state || current)
          save(feeds: normalized[:feeds], articles: normalized[:articles])
        end

        private

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

          version = payload[:schema_version]
          unless version.to_i == SCHEMA_VERSION
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
          {
            schema_version: SCHEMA_VERSION,
            feeds: Array(payload[:feeds]).map { |row| Shoko::Core::Models::RssFeed.from_h(row) },
            articles: Array(payload[:articles]).map do |row|
              Shoko::Core::Models::RssArticle.from_h(row)
            end,
          }
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

          Shoko::Core::Models::RssFeed.from_h(feed)
        end

        def coerce_article(article)
          return article if article.is_a?(Shoko::Core::Models::RssArticle)

          Shoko::Core::Models::RssArticle.from_h(article)
        end

        def raise_storage_error(operation, error)
          raise error if error.is_a?(Shoko::Error)

          raise Shoko::StorageError.new(operation, @file_path, error.message)
        end

        def normalize_hash_keys(payload)
          return payload unless payload.is_a?(Hash)

          payload.each_with_object({}) do |(key, value), acc|
            normalized_key = key.is_a?(String) ? key.to_sym : key
            acc[normalized_key] = value
          end
        end

        def serialized_snapshot(feeds:, articles:)
          {
            schema_version: SCHEMA_VERSION,
            feeds: Array(feeds).map { |feed| coerce_feed(feed).to_h },
            articles: Array(articles).map { |article| coerce_article(article).to_h },
          }
        end

        def persist_payload(payload)
          @file_utils.mkdir_p(File.dirname(@file_path))
          @atomic_file_writer.write(@file_path, JSON.pretty_generate(payload))
        end
      end
    end
  end
end
