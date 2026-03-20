# frozen_string_literal: true

require_relative '../../../../shared/hash_normalizer'

require_relative '../../pagination'
require_relative '../../../models/content_block'

module Shoko
  module Core
    module Services
      module Pagination
        module Internal
          # Builds dynamic pagination page data for all chapters.
          # Produces the same page hashes used by PageCalculatorService.
          # Not DI-registered; used internally by the facade service.
          class DynamicPageMapBuilder
            BuildRequest = Data.define(
              :doc,
              :col_width,
              :lines_per_page,
              :text_metrics,
              :line_wrapper,
              :chapter_formatter,
              :config
            )
            private_constant :BuildRequest

            # @param text_metrics [Core::Ports::Outbound::TextMetrics] Text metrics adapter (required)
            def self.build(doc, col_width, lines_per_page, text_metrics:, line_wrapper: nil, chapter_formatter: nil,
                           config: nil, &)
              request = build_request(
                doc,
                col_width,
                lines_per_page,
                text_metrics: text_metrics,
                line_wrapper: line_wrapper,
                chapter_formatter: chapter_formatter,
                config: config
              )
              build_pages_data(request, &)
            end

            class << self
              private

              def build_request(
                doc,
                col_width,
                lines_per_page,
                text_metrics:,
                line_wrapper:,
                chapter_formatter:,
                config:
              )
                raise ArgumentError, 'text_metrics is required' unless text_metrics

                BuildRequest.new(
                  doc: doc,
                  col_width: col_width,
                  lines_per_page: lines_per_page,
                  text_metrics: text_metrics,
                  line_wrapper: line_wrapper,
                  chapter_formatter: chapter_formatter,
                  config: config
                )
              end

              def build_pages_data(request)
                pages_data = []
                total = request.doc.chapter_count

                total.times do |chapter_idx|
                  built = chapter_pages_appended?(pages_data, request, chapter_idx)
                  yield(chapter_idx + 1, total) if built && block_given?
                end

                pages_data
              end

              def chapter_pages_appended?(pages_data, request, chapter_idx)
                chapter = request.doc.get_chapter(chapter_idx)
                return false unless chapter

                pages = paginate_lines(wrapped_lines(request, chapter, chapter_idx), request.lines_per_page)
                page_count = [pages.length, 1].max
                pages.each_with_index do |page, page_idx|
                  pages_data << build_page_payload(page, chapter_idx, page_idx, page_count)
                end
                true
              end

              def build_page_payload(page, chapter_idx, page_idx, page_count)
                {
                  chapter_index: chapter_idx,
                  page_in_chapter: page_idx,
                  total_pages_in_chapter: page_count,
                  start_line: page[:start_line],
                  end_line: page[:end_line],
                  lines: page[:lines],
                }
              end

              def paginate_lines(lines, lines_per_page)
                per_page = [lines_per_page.to_i, 1].max
                list = Array(lines)
                return [empty_page] if list.empty?

                build_pages(list, per_page)
              rescue Shoko::Error
                [fallback_page(list)]
              end

              def build_pages(list, per_page)
                pages = []
                index = 0

                while index < list.length
                  page_result = build_single_page(list, index, per_page)
                  pages << page_result[:page]
                  index = page_result[:next_index]
                end

                pages
              end

              def build_single_page(list, start_index, per_page)
                page_lines = []
                index = start_index

                while page_lines.length < per_page && index < list.length
                  result = collect_next_lines(list, index, per_page - page_lines.length, page_lines.empty?)
                  break if result.nil?

                  page_lines.concat(result[:lines])
                  index = result[:next_index]
                end

                {
                  page: { start_line: start_index, end_line: start_index + page_lines.length - 1, lines: page_lines },
                  next_index: index,
                }
              end

              def collect_next_lines(list, index, remaining, page_empty)
                group_len = image_group_length(list, index)

                return nil if group_len && group_len > remaining && !page_empty

                if group_len
                  take = [group_len, remaining].min
                  { lines: list[index, take], next_index: index + take }
                else
                  { lines: [list[index]], next_index: index + 1 }
                end
              end

              def empty_page
                { start_line: 0, end_line: -1, lines: [] }
              end

              def fallback_page(list)
                { start_line: 0, end_line: [list.length - 1, -1].max, lines: list }
              end

              def image_group_length(lines, start_index)
                meta = metadata_for(lines[start_index])
                return nil unless image_render_start?(meta)

                src = extract_image_src(meta)
                return nil if src.nil?

                count_contiguous_image_lines(lines, start_index, src)
              end

              def image_render_start?(meta)
                return false unless meta

                has_render = meta[:image_render].is_a?(Hash)
                return false unless has_render

                meta[:image_render_line] == true
              end

              def extract_image_src(meta)
                image = meta[:image].is_a?(Hash) ? meta[:image] : {}
                src = image[:src]
                src.to_s.empty? ? nil : src.to_s
              end

              def count_contiguous_image_lines(lines, start_index, src)
                index = start_index
                index += 1 while index < lines.length && same_image_block?(lines[index], src)
                index - start_index
              end

              def same_image_block?(line, expected_src)
                meta = metadata_for(line)
                return false unless meta

                block_type = meta[:block_type]
                return false unless block_type == :image || block_type.to_s == 'image'

                cur_src = extract_image_src(meta)
                cur_src == expected_src
              end

              def metadata_for(line)
                return nil unless line.is_a?(Shoko::Core::Models::DisplayLine)

                meta = line.metadata
                Shoko::Shared::HashNormalizer.deep_symbolize(meta)
              end

              def wrapped_lines(request, chapter, chapter_idx)
                return [] if request.col_width.to_i <= 0 || chapter.nil?

                try_formatter(request, chapter_idx) ||
                  try_wrapper(request, chapter, chapter_idx) ||
                  wrap_plain_lines(chapter.lines || [], request.col_width, request.text_metrics)
              end

              def try_formatter(request, chapter_idx)
                formatter = request.chapter_formatter
                return nil unless formatter

                lines = formatter.wrap_all(
                  request.doc,
                  chapter_idx,
                  request.col_width,
                  config: request.config,
                  lines_per_page: request.lines_per_page
                )
                lines && !lines.empty? ? lines : nil
              end

              def try_wrapper(request, chapter, chapter_idx)
                wrapper = request.line_wrapper
                return nil unless wrapper

                lines = wrapper.wrap_lines(chapter.lines || [], chapter_idx, request.col_width)
                lines && !lines.empty? ? lines : nil
              end

              def wrap_plain_lines(lines, width, text_metrics)
                return [] if lines.empty? || width <= 0

                lines.each_with_object([]) do |line, acc|
                  next if line.nil?

                  if line.strip.empty?
                    acc << ''
                  else
                    segments = text_metrics.wrap_plain_text(line, width)
                    acc.concat(segments)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
