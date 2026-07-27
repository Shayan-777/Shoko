# frozen_string_literal: true

require 'shoko/core/models/content_block'
require 'shoko/core/models/text_segment'
require 'shoko/shared/text_sanitizer'

module Shoko
  module Adapters
    module Rss
      # Makes parsed article blocks safe and bounded before they are stored.
      #
      # Block text comes from arbitrary third-party pages, so it crosses the
      # same trust boundary the flat article text does and gets the same
      # treatment: control sequences stripped (an ANSI escape in an article
      # would otherwise repaint the terminal), and a hard ceiling on total text
      # so one enormous page cannot bloat the cache or the state tree.
      #
      # The ceiling is applied across the whole article, not per block, and it
      # truncates the final segment on a grapheme boundary.
      class ArticleBlockSanitizer
        ContentBlock = Shoko::Core::Models::ContentBlock
        TextSegment = Shoko::Core::Models::TextSegment
        # Structural blocks carry meaning with no text of their own.
        TEXTLESS_TYPES = %i[rule].freeze

        def initialize(max_text_length:, text_sanitizer: Shoko::Shared::TextSanitizer)
          @max_text_length = max_text_length
          @text_sanitizer = text_sanitizer
        end

        # @param blocks [Array<ContentBlock>]
        # @return [Array<ContentBlock>] sanitized, within the text ceiling
        def call(blocks)
          budget = @max_text_length
          Array(blocks).each_with_object([]) do |block, kept|
            break kept if budget <= 0

            sanitized = sanitize_block(block, budget)
            next unless sanitized

            budget -= sanitized.text.length
            kept << sanitized
          end
        end

        private

        def sanitize_block(block, budget)
          segments = sanitize_segments(block.segments, budget)
          return nil if segments.empty? && !TEXTLESS_TYPES.include?(block.type)

          ContentBlock.new(
            type: block.type,
            segments: segments,
            level: block.level,
            metadata: sanitize_metadata(block.metadata)
          )
        end

        def sanitize_segments(segments, budget)
          remaining = budget
          Array(segments).filter_map do |segment|
            next if remaining <= 0

            # Newlines are structure here — a block IS a line — so any newline
            # inside a segment is markup noise, not content.
            text = @text_sanitizer.sanitize(segment.text.to_s, preserve_newlines: false, preserve_tabs: false)
            next if text.empty?

            bounded = truncate_graphemes(text, remaining)
            next if bounded.empty?

            remaining -= bounded.length
            TextSegment.new(text: bounded, styles: sanitize_values(segment.styles))
          end
        end

        def truncate_graphemes(text, limit)
          return text if text.length <= limit

          output = +''
          text.each_grapheme_cluster do |cluster|
            break if output.length + cluster.length > limit

            output << cluster
          end
          output
        end

        def sanitize_metadata(metadata)
          sanitize_values(metadata)
        end

        # List markers and link hrefs are rendered too, so any String carried
        # alongside a block or segment gets the same treatment as its text.
        def sanitize_values(values)
          (values || {}).each_with_object({}) do |(key, value), acc|
            acc[key] = value.is_a?(String) ? @text_sanitizer.sanitize(value, preserve_newlines: false) : value
          end
        end
      end
    end
  end
end
