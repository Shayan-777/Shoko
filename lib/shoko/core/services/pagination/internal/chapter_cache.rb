# frozen_string_literal: true

require_relative '../../pagination'
require_relative '../../../../adapters/output/terminal/text_metrics'

module Shoko
  module Core
    module Services
      module Pagination
        module Internal
          # Caches wrapped lines for chapters to avoid recomputation
          # Internal helper used by WrappingService; not DI-registered.
          class ChapterCache
            def initialize
              @wrapped_cache = {}
              @cache_key_memo = {}
            end

            # Get wrapped lines for chapter and width
            # @param chapter_index [Integer]
            # @param lines [Array<String>]
            # @param width [Integer]
            # @return [Array<String>]
            def get_wrapped_lines(chapter_index, lines, width)
              cache_key = generate_cache_key(chapter_index, width)
              cached = @wrapped_cache[cache_key]
              memo_id = @cache_key_memo[cache_key]
              return cached if cached && memo_id == lines.object_id

              wrapped = wrap_lines_internal(lines, width)
              @wrapped_cache[cache_key] = wrapped
              @cache_key_memo[cache_key] = lines.object_id
              wrapped
            end

            # Clear cached entries for given width
            def clear_cache_for_width(width)
              @wrapped_cache.delete_if { |key, _| key.end_with?("_#{width}") }
            end

            private

            def generate_cache_key(chapter_index, width)
              "#{chapter_index}_#{width}"
            end

            def wrap_lines_internal(lines, width)
              return [] if lines.nil? || width < 1

              wrapped = []
              lines.each do |line|
                next if line.nil?

                if line.strip.empty?
                  wrapped << ''
                else
                  segments = Shoko::Adapters::Output::Terminal::TextMetrics.wrap_plain_text(line, width)
                  wrapped.concat(segments)
                end
              end
              wrapped
            end
          end
        end
      end
    end
  end
end
