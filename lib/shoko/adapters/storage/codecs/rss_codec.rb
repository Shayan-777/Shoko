# frozen_string_literal: true

require 'shoko/adapters/support/content_block_codec'
require 'shoko/core/models/rss_article'
require 'shoko/core/models/rss_feed'
require 'shoko/shared/hash_normalizer'

module Shoko
  module Adapters
    module Storage
      module Codecs
        # Owns the persisted RSS feed, article metadata, and body shapes.
        module RssCodec
          module_function

          def load_feed(payload)
            fields = normalize(payload, 'rss feed')
            Core::Models::RssFeed.new(**slice(fields, Core::Models::RssFeed.members))
          end

          def dump_feed(feed)
            feed.to_h
          end

          def load_article(payload)
            fields = normalize(payload, 'rss article')
            attributes = slice(fields, Core::Models::RssArticle.members)
            attributes[:content_blocks] = Shoko::Adapters::Support::ContentBlockCodec.load(
              attributes[:content_blocks]
            )
            Core::Models::RssArticle.new(**attributes)
          end

          def dump_article(article)
            article.to_h.merge(
              content_blocks: Shoko::Adapters::Support::ContentBlockCodec.dump(article.content_blocks)
            )
          end

          def load_body(payload)
            fields = normalize(payload, 'rss article body')
            {
              content: fields[:content].to_s,
              content_blocks: Shoko::Adapters::Support::ContentBlockCodec.load(fields[:content_blocks]),
            }
          end

          def dump_body(article)
            {
              content: article.content,
              content_blocks: Shoko::Adapters::Support::ContentBlockCodec.dump(article.content_blocks),
            }
          end

          def normalize(payload, label)
            raise ArgumentError, "#{label} payload must be a Hash, got #{payload.class}" unless payload.is_a?(Hash)

            Shared::HashNormalizer.symbolize_keys(payload)
          end
          private_class_method :normalize

          def slice(fields, members)
            members.to_h { |field| [field, fields[field]] }
          end
          private_class_method :slice
        end
      end
    end
  end
end
