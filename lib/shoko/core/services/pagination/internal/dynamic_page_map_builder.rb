# frozen_string_literal: true

require 'shoko/shared/hash_normalizer'
require 'shoko/core/models/block_type'

require_relative '../../pagination'

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

            KEEP_LINES_AFTER_HEADING = 2

            # @param text_metrics [Object] Text metrics collaborator (required)
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
                  return nil if !page_empty && break_line_early?(list, index, remaining)

                  { lines: [list[index]], next_index: index + 1 }
                end
              end

              # Page-break quality: a heading never strands at the bottom of a
              # page without room for its first lines of prose, and a page's
              # last slot never takes the lone first line of a paragraph.
              def break_line_early?(list, index, remaining)
                heading_break_needed?(list, index, remaining) ||
                  orphan_break_needed?(list, index, remaining)
              end

              def heading_break_needed?(list, index, remaining)
                meta = metadata_for(list[index])
                return false unless block_type_of(meta) == :heading
                return false if block_type_of(metadata_for(index.positive? ? list[index - 1] : nil)) == :heading

                heading_keep_length(list, index) > remaining
              end

              def heading_keep_length(list, index)
                cursor = index
                cursor += 1 while cursor < list.length && block_type_of(metadata_for(list[cursor])) == :heading
                cursor += 1 while cursor < list.length && blank_line?(list[cursor])
                (cursor - index) + KEEP_LINES_AFTER_HEADING
              end

              def orphan_break_needed?(list, index, remaining)
                return false unless remaining == 1

                type = block_type_of(metadata_for(list[index]))
                return false unless %i[paragraph quote].include?(type)
                return false unless index.zero? || blank_line?(list[index - 1])

                block_type_of(metadata_for(list[index + 1])) == type && !blank_line?(list[index + 1])
              end

              def block_type_of(meta)
                return nil unless meta

                Shoko::Core::Models::BlockType.canonical(meta[:block_type])
              end

              def blank_line?(line)
                return true if line.nil?
                return line.strip.empty? if line.is_a?(String)

                meta = metadata_for(line)
                meta && meta[:spacer] ? true : line.text.to_s.strip.empty?
              end

              def empty_page
                { start_line: 0, end_line: -1, lines: [] }
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
                return false unless Shoko::Core::Models::BlockType.image?(meta[:block_type])

                cur_src = extract_image_src(meta)
                cur_src == expected_src
              end

              # Read line metadata while staying free of presentation
              # type references in core. Plain Strings carry no metadata;
              # everything else is treated as a display-line-shaped object
              # exposing `#metadata`. NoMethodError surfaces naturally if
              # the line is some other unsupported shape.
              def metadata_for(line)
                return nil if line.nil? || line.is_a?(String)

                meta = line.metadata
                Shoko::Shared::HashNormalizer.deep_symbolize(meta)
              end

              def wrapped_lines(request, chapter, chapter_idx)
                return [] if request.col_width.to_i <= 0 || chapter.nil?

                plain = plain_lines_for(request, chapter, chapter_idx)
                try_formatter(request, chapter_idx) ||
                  try_wrapper(request, plain, chapter_idx) ||
                  wrap_plain_lines(plain, request.col_width, request.text_metrics)
              end

              # Source the chapter's parsed plain lines from the formatter
              # if available (replaces the previous reliance on
              # `chapter.lines` having been back-written by an adapter).
              # Falls back to `chapter.lines` for importer formats that
              # populate plain lines at import time.
              def plain_lines_for(request, chapter, chapter_idx)
                formatter = request.chapter_formatter
                if formatter
                  lines = formatter.plain_lines_for(request.doc, chapter_idx)
                  return Array(lines) unless lines.nil? || lines.empty?
                end
                Array(chapter.lines)
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

              def try_wrapper(request, plain_lines, chapter_idx)
                wrapper = request.line_wrapper
                return nil unless wrapper

                lines = wrapper.wrap_lines(plain_lines, chapter_idx, request.col_width)
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
