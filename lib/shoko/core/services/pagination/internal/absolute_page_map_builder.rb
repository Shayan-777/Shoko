# frozen_string_literal: true

require_relative '../../pagination'
module Shoko
  module Core
    module Services
      module Pagination
        module Internal
          # Small helper to compute absolute page maps per chapter.
          # Encapsulates the per-chapter wrapping + page counting loop.
          class AbsolutePageMapBuilder
            def self.build(doc, col_width, lines_per_page, wrapper = nil, text_metrics: nil)
              total = doc.chapter_count
              page_map = []
              total.times do |i|
                chapter = doc.get_chapter(i)
                lines = chapter&.lines || []

                wrapped = if wrapper
                            wrapper.wrap_lines(lines, i, col_width)
                          else
                            wrap_with_text_metrics(lines, col_width, text_metrics)
                          end

                pages = (wrapped.size.to_f / [lines_per_page, 1].max).ceil
                page_map << pages
                yield(i + 1, total) if block_given?
              end
              page_map
            end

            class << self
              private

              def wrap_with_text_metrics(lines, col_width, text_metrics)
                raise ArgumentError, 'text_metrics is required when wrapper is nil' unless text_metrics

                width = [col_width.to_i, 1].max
                Array(lines).each_with_object([]) do |line, wrapped|
                  next if line.nil?

                  text = line.to_s
                  if text.strip.empty?
                    wrapped << ''
                    next
                  end

                  segments = Array(text_metrics.wrap_plain_text(text, width))
                  wrapped.concat(segments.empty? ? [text] : segments)
                rescue StandardError
                  wrapped << text
                end
              end
            end
          end
        end
      end
    end
  end
end
