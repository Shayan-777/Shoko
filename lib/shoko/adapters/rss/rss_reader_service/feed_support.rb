# frozen_string_literal: true

require 'uri'

module Shoko
  module Adapters
    module Rss
      # Feed record builders and feed identity helpers for the RSS reader service.
      module RssReaderServiceFeedSupport
        private

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
      end
    end
  end
end
