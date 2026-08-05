# frozen_string_literal: true

require 'shoko/core/models/content_block'
require 'shoko/core/models/content_block_payload'
require 'shoko/shared/resilient_diagnostics'
require 'shoko/shared/text_sanitizer'
require_relative 'article_block_sanitizer'

module Shoko
  module Adapters
    module Rss
      # Fetches and normalizes the full body of one RSS article.
      #
      # This collaborator owns the enrichment policy and its parser/fetcher
      # failure boundary. Repository coordination and read/star state remain
      # with RssReaderService.
      class ArticleBodyHydrator
        Body = Data.define(:summary, :content, :content_blocks, :fetched_at)

        MAX_SUMMARY_LENGTH = 1600
        MAX_CONTENT_LENGTH = 12_000
        FULL_CONTENT_MIN_LENGTH = 1000
        FULL_CONTENT_GAIN_THRESHOLD = 200

        def initialize(fetcher:, wall_clock:, text_sanitizer: nil, logger: nil)
          @fetcher = fetcher
          @wall_clock = wall_clock
          @text_sanitizer = text_sanitizer
          @logger = logger
          @block_sanitizer = ArticleBlockSanitizer.new(max_text_length: MAX_CONTENT_LENGTH)
        end

        def hydrate(article)
          payload = hydration_payload(article)
          enriched = enrich(payload)
          summary = sanitized_text(enriched[:summary], MAX_SUMMARY_LENGTH)
          content_source = enriched[:content].to_s.strip.empty? ? summary : enriched[:content]
          Body.new(
            summary: summary,
            content: sanitized_text(content_source, MAX_CONTENT_LENGTH),
            content_blocks: sanitized_blocks(enriched[:content_blocks]),
            fetched_at: @wall_clock.utc_now.iso8601
          )
        end

        def apply(article, body)
          article.with(
            summary: body.summary,
            content: body.content,
            content_blocks: body.content_blocks,
            fetched_at: body.fetched_at
          )
        end

        def changed?(article, body)
          article.summary != body.summary ||
            article.content != body.content ||
            article.content_blocks != body.content_blocks
        end

        private

        def hydration_payload(article)
          payload = article.to_h
          payload[:content] = '' if article.content == article.summary
          payload
        end

        def enrich(payload)
          return payload unless should_fetch?(payload)

          fetched = @fetcher.fetch(payload[:url])
          return payload unless more_complete?(payload, fetched.text)

          payload.merge(
            content: fetched.text,
            content_blocks: fetched.blocks,
            summary: summary_for(payload[:summary], fetched.text)
          )
        # resilient-boundary
        rescue StandardError => e
          record_hydration_error(payload, e)
          payload
        end

        def should_fetch?(payload)
          return false unless @fetcher
          return false if payload[:url].to_s.strip.empty?

          existing = best_existing_text(payload)
          existing.empty? || truncated?(existing, payload[:summary].to_s.strip)
        end

        def best_existing_text(payload)
          content = payload[:content].to_s.strip
          content.empty? ? payload[:summary].to_s.strip : content
        end

        def truncated?(content, summary)
          content.length < FULL_CONTENT_MIN_LENGTH &&
            content.length <= summary.length + FULL_CONTENT_GAIN_THRESHOLD
        end

        def more_complete?(payload, full_content)
          fetched = full_content.to_s.strip
          return false if fetched.empty?

          existing = best_existing_text(payload)
          return fetched.length > existing.length if payload[:content].to_s.strip.empty?

          fetched.length > existing.length + FULL_CONTENT_GAIN_THRESHOLD
        end

        def summary_for(current, full_content)
          summary = current.to_s.strip
          return summary unless summary.empty?

          full_content.to_s.strip.gsub(/\s+/, ' ')[0, 320].to_s.strip
        end

        def sanitized_text(text, max_length)
          value = if @text_sanitizer
                    @text_sanitizer.sanitize(text.to_s, preserve_newlines: true, max_length: max_length)
                  else
                    Shoko::Shared::TextSanitizer.sanitize(
                      text.to_s,
                      preserve_newlines: true,
                      preserve_tabs: false
                    )[0, max_length]
                  end
          value.to_s.strip
        end

        def sanitized_blocks(blocks)
          return [] if blocks.nil? || Array(blocks).empty?

          parsed = if Array(blocks).first.is_a?(Shoko::Core::Models::ContentBlock)
                     blocks
                   else
                     Shoko::Core::Models::ContentBlockPayload.load(blocks)
                   end
          Shoko::Core::Models::ContentBlockPayload.dump(@block_sanitizer.call(parsed))
        end

        def record_hydration_error(payload, error)
          Shoko::Shared::ResilientDiagnostics.debug(
            @logger,
            'rss_reader.article_content_fetch_failed',
            url: payload[:url],
            error_class: error.class.name,
            error: error.message
          )
          nil
        end
      end
    end
  end
end
