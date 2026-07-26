# frozen_string_literal: true

require 'shoko/shared/hash_normalizer'
require_relative 'content_block_payload'

module Shoko
  module Core
    module Models
      # Durable RSS article payload stored in the local reader cache.
      RssArticle = Data.define(
        :id,
        :feed_id,
        :guid,
        :title,
        :author,
        :summary,
        :content,
        :content_blocks,
        :url,
        :published_at,
        :read,
        :starred,
        :fetched_at
      ) do
        def initialize(id:, feed_id:, title:, guid: nil, author: nil, summary: nil, content: nil,
                       content_blocks: nil, url: nil,
                       published_at: nil, read: false, starred: false, fetched_at: nil)
          super(
            **normalized_attributes(
              id: id,
              feed_id: feed_id,
              title: title,
              guid: guid,
              author: author,
              summary: summary,
              content: content,
              content_blocks: content_blocks,
              url: url,
              published_at: published_at,
              read: read,
              starred: starred,
              fetched_at: fetched_at
            )
          )
        end

        # Every field is passed explicitly, including missing ones, so the
        # constructor's own validation reports a missing id or title rather
        # than Ruby reporting a missing keyword argument.
        def self.from_h(payload)
          data = normalize_hash(payload)
          new(**members.to_h { |field| [field, data[field]] })
        end

        def to_h
          {
            id: id,
            feed_id: feed_id,
            guid: guid,
            title: title,
            author: author,
            summary: summary,
            content: content,
            content_blocks: content_blocks,
            url: url,
            published_at: published_at,
            read: read,
            starred: starred,
            fetched_at: fetched_at,
          }
        end

        private

        def self.normalize_hash(payload)
          raise ArgumentError, "rss article payload must be a Hash, got #{payload.class}" unless payload.is_a?(Hash)

          Shoko::Shared::HashNormalizer.symbolize_keys(payload)
        end

        def blank_to_nil(value)
          text = value.to_s.strip
          return nil if text.empty?

          text.freeze
        end

        def blank_to_empty(value)
          text = value.to_s
          return '' if text.empty?

          text.freeze
        end

        def normalized_attributes(attributes)
          required_article_attributes(attributes).merge(optional_article_attributes(attributes))
        end

        def required_article_attributes(attributes)
          {
            id: required_text(attributes[:id], 'rss article id is required').freeze,
            feed_id: required_text(attributes[:feed_id], 'rss article feed_id is required').freeze,
            title: required_text(attributes[:title], 'rss article title is required').freeze,
          }
        end

        def optional_article_attributes(attributes)
          {
            guid: blank_to_nil(attributes[:guid]),
            author: blank_to_nil(attributes[:author]),
            summary: blank_to_empty(attributes[:summary]),
            content: blank_to_empty(attributes[:content]),
            content_blocks: normalized_blocks(attributes[:content_blocks]),
            url: blank_to_nil(attributes[:url]),
            published_at: blank_to_nil(attributes[:published_at]),
            read: attributes[:read] == true,
            starred: attributes[:starred] == true,
            fetched_at: blank_to_nil(attributes[:fetched_at]),
          }
        end

        # Stored as plain payloads so the article stays JSON-serializable and
        # admissible into the frozen state tree. Normalizing through the
        # model's own round trip means a cache written by an older build (no
        # blocks) and one written by a newer build both load to a valid value.
        def normalized_blocks(value)
          return [].freeze if value.nil?

          ContentBlockPayload.dump(ContentBlockPayload.load(value)).freeze
        end

        def required_text(value, message)
          text = value.to_s.strip
          raise ArgumentError, message if text.empty?

          text
        end
      end
    end
  end
end
