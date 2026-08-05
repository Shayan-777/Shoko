# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Durable RSS feed subscription metadata.
      RssFeed = Data.define(
        :id,
        :url,
        :title,
        :site_url,
        :etag,
        :last_modified,
        :added_at,
        :last_synced_at,
        :sync_error
      ) do
        def initialize(id:, url:, title:, site_url: nil, etag: nil, last_modified: nil, added_at: nil,
                       last_synced_at: nil, sync_error: nil)
          super(
            **normalized_attributes(
              id: id,
              url: url,
              title: title,
              site_url: site_url,
              etag: etag,
              last_modified: last_modified,
              added_at: added_at,
              last_synced_at: last_synced_at,
              sync_error: sync_error
            )
          )
        end

        private

        def blank_to_nil(value)
          text = value.to_s.strip
          return nil if text.empty?

          text.freeze
        end

        def normalized_attributes(attributes)
          normalized_title = attributes[:title].to_s.strip

          required_feed_attributes(attributes, normalized_title).merge(optional_feed_attributes(attributes))
        end

        def required_feed_attributes(attributes, normalized_title)
          {
            id: required_text(attributes[:id], 'rss feed id is required').freeze,
            url: required_text(attributes[:url], 'rss feed url is required').freeze,
            title: (normalized_title.empty? ? 'Untitled Feed' : normalized_title).freeze,
          }
        end

        def optional_feed_attributes(attributes)
          {
            site_url: blank_to_nil(attributes[:site_url]),
            etag: blank_to_nil(attributes[:etag]),
            last_modified: blank_to_nil(attributes[:last_modified]),
            added_at: blank_to_nil(attributes[:added_at]),
            last_synced_at: blank_to_nil(attributes[:last_synced_at]),
            sync_error: blank_to_nil(attributes[:sync_error]),
          }
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
