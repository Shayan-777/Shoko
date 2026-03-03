# frozen_string_literal: true

require 'digest/sha1'

require_relative '../../base_adapter'
require_relative '../../../core/models/content_block'
require_relative '../../../core/ports/outbound/chapter_formatter'
require_relative '../terminal/text_metrics'
require_relative '../kitty/kitty_graphics'

module Shoko
  module Adapters
    module Output
      module Formatting
        # Responsible for transforming chapter raw content into semantic blocks and
        # producing display-ready wrapped lines (with style metadata) for renderers.
        class FormattingService < Shoko::Adapters::BaseAdapter
          include Shoko::Core::Ports::Outbound::ChapterFormatter

          # Cached chapter formatting results.
          FormattedChapter = Struct.new(:blocks, :plain_lines, :checksum, keyword_init: true)
          private_constant :FormattedChapter

          # Maximum number of chapters to keep in cache (LRU eviction)
          MAX_CHAPTER_CACHE_SIZE = 50
          MAX_WRAPPED_CACHE_SIZE = 50

          # @param xhtml_parser_factory [Object, nil] Factory for creating XHTML parsers
          # @param format_parser_resolver [Proc, nil] ->(raw, chapter) returns parser based on format
          # @param logger [Object, nil] Optional logger
          def initialize(xhtml_parser_factory: nil, format_parser_resolver: nil, runtime_config: nil, logger: nil)
            super(logger: logger)
            @chapter_cache = {}
            @chapter_cache_order = []
            @wrapped_cache = Hash.new { |h, k| h[k] = {} }
            @wrapped_cache_order = []
            @parser_factory = xhtml_parser_factory
            @format_parser_resolver = format_parser_resolver
            @runtime_config = runtime_config
          end

          # Ensure the provided chapter has semantic blocks + plain lines.
          #
          # @param document [BookDocument]
          # @param chapter_index [Integer]
          # @param chapter [Core::Models::Chapter]
          def ensure_formatted!(document, chapter_index, chapter)
            ensure_formatted_core(document, chapter_index, chapter)
          rescue Shoko::FormattingError
            raise
          rescue StandardError => e
            logger&.error('Formatting service failed', error: e.message)
            nil
          end

          # Retrieve wrapped, display-ready lines for a chapter window.
          # Returns an array of Core::Models::DisplayLine, falling back to plain
          # strings when formatting is unavailable.
          #
          # @param document [BookDocument]
          # @param chapter_index [Integer]
          # @param width [Integer]
          # @param offset [Integer]
          # @param length [Integer]
          # @param config [Object,nil] state store-like object responding to #get
          # @param lines_per_page [Integer,nil] optional page height hint for image sizing
          # @return [Array<Core::Models::DisplayLine,String>]
          def wrap_window(document, chapter_index, width, offset:, length:, config: nil, lines_per_page: nil)
            width_i = width.to_i
            length_i = length.to_i
            offset_i = offset.to_i
            return [] if width_i <= 0 || length_i <= 0

            chapter = document&.get_chapter(chapter_index)
            return [] unless chapter

            formatted = ensure_formatted!(document, chapter_index, chapter)
            return plain_window(chapter, offset: offset_i, length: length_i) unless formatted

            chapter_source_path = chapter_source_path_for(chapter)
            wrapped = wrapped_lines_for(document, chapter_index, formatted, width_i,
                                        chapter_source_path: chapter_source_path, config: config,
                                        lines_per_page: lines_per_page)
            window_slice(wrapped, offset: offset_i, length: length_i)
          end

          # Retrieve all wrapped lines for a chapter at the provided width.
          #
          # @return [Array<Core::Models::DisplayLine>]
          def wrap_all(document, chapter_index, width, config: nil, lines_per_page: nil)
            return [] if width.to_i <= 0

            chapter = document&.get_chapter(chapter_index)
            return [] unless chapter

            formatted = ensure_formatted!(document, chapter_index, chapter)
            return chapter.lines || [] unless formatted

            chapter_source_path = chapter_source_path_for(chapter)
            wrapped_lines_for(document, chapter_index, formatted, width.to_i,
                              chapter_source_path: chapter_source_path, config: config,
                              lines_per_page: lines_per_page)
          end

          private

          def wrapped_lines_for(document, chapter_index, formatted, width, chapter_source_path:, config:,
                                lines_per_page: nil)
            width_key = width.to_i
            cache_key = chapter_cache_key(document, chapter_index)
            variant = wrap_variant(config)
            max_image_rows = max_image_rows_for(lines_per_page)
            composite_key = wrapped_composite_key(width_key, variant, max_image_rows)
            evict_wrapped_cache_if_needed(cache_key)
            cache_for_chapter = @wrapped_cache[cache_key]
            cache_for_chapter[composite_key] ||= build_wrapped_lines(
              formatted.blocks,
              width: width_key,
              chapter_index: chapter_index,
              chapter_source_path: chapter_source_path,
              rendering_mode: rendering_mode_for(variant),
              max_image_rows: max_image_rows
            )
          end

          def checksum_for(content)
            Digest::SHA1.hexdigest(content.to_s)
          end

          def apply_formatted_to_chapter(chapter, formatted)
            chapter.blocks = formatted.blocks
            return unless chapter.lines.nil? || chapter.lines.empty?

            chapter.lines = formatted.plain_lines
          end

          def chapter_cache_key(document, chapter_index)
            source = document.canonical_path
            "#{source}:#{chapter_index}"
          end

          def build_parser(raw, chapter: nil)
            # Try format-aware resolver first (dispatches based on chapter metadata[:format])
            if @format_parser_resolver
              parser = @format_parser_resolver.call(raw, chapter)
              return parser if parser
            end

            # Fall back to the default XHTML parser factory
            return nil unless @parser_factory

            @parser_factory.call(raw)
          rescue StandardError
            nil
          end

          def build_plain_lines(blocks)
            PlainLinesBuilder.build(blocks)
          end

          def chapter_source_path_for(chapter)
            metadata = chapter.metadata
            return nil unless metadata

            metadata[:source_path] || metadata['source_path'] || metadata[:href] || metadata['href']
          rescue StandardError
            nil
          end

          def wrap_variant(config)
            Shoko::Adapters::Output::Kitty::KittyGraphics.enabled_for?(config) ? 'img' : 'txt'
          rescue StandardError
            'txt'
          end

          def raw_content_for(chapter)
            chapter.raw_content
          end

          def formatted_chapter_from_blocks(blocks, checksum)
            FormattedChapter.new(
              blocks: blocks,
              plain_lines: build_plain_lines(blocks),
              checksum: checksum
            )
          end

          def plain_window(chapter, offset:, length:)
            (chapter.lines || [])[offset, length] || []
          end

          def window_slice(lines, offset:, length:)
            (lines || [])[offset, length] || []
          end

          def max_image_rows_for(lines_per_page)
            rows = lines_per_page.to_i
            rows.positive? ? rows : nil
          end

          def wrapped_composite_key(width_key, variant, max_image_rows)
            return "#{width_key}|#{variant}" unless variant == 'img' && max_image_rows

            "#{width_key}|#{variant}|#{max_image_rows}"
          end

          def rendering_mode_for(variant)
            variant == 'img' ? :images : :text
          end

          def build_wrapped_lines(blocks, width:, chapter_index:, chapter_source_path:, rendering_mode:, max_image_rows:)
            LineAssembler.new(
              width,
              chapter_index: chapter_index,
              chapter_source_path: chapter_source_path,
              rendering_mode: rendering_mode,
              max_image_rows: max_image_rows,
              runtime_config: @runtime_config
            ).build(blocks)
          end

          def ensure_formatted_core(document, chapter_index, chapter)
            return nil unless chapter

            raw = raw_content_for(chapter)
            cache_key = chapter_cache_key(document, chapter_index)
            cached = @chapter_cache[cache_key]
            checksum = checksum_for(raw)
            return cached if cache_hit?(cached, checksum, chapter)
            return cached if raw.nil?

            formatted = build_formatted_from_raw(raw, checksum, chapter: chapter)
            return cached unless formatted

            store_formatted_chapter(cache_key, formatted, chapter)
          end

          def cache_hit?(cached, checksum, chapter)
            return false unless cached && cached.checksum == checksum

            apply_formatted_to_chapter(chapter, cached)
            true
          end

          def build_formatted_from_raw(raw, checksum, chapter: nil)
            parser = build_parser(raw, chapter: chapter)
            return nil unless parser

            formatted_chapter_from_blocks(parser.parse, checksum)
          end

          def store_formatted_chapter(cache_key, formatted, chapter)
            evict_chapter_cache_if_needed(cache_key)
            @chapter_cache[cache_key] = formatted
            @wrapped_cache.delete(cache_key)
            @wrapped_cache_order.delete(cache_key)
            apply_formatted_to_chapter(chapter, formatted)
            formatted
          end

          def evict_chapter_cache_if_needed(new_key)
            @chapter_cache_order.delete(new_key)
            @chapter_cache_order << new_key

            while @chapter_cache_order.length > MAX_CHAPTER_CACHE_SIZE
              oldest = @chapter_cache_order.shift
              @chapter_cache.delete(oldest)
              @wrapped_cache.delete(oldest)
              @wrapped_cache_order.delete(oldest)
            end
          end

          def evict_wrapped_cache_if_needed(cache_key)
            @wrapped_cache_order.delete(cache_key)
            @wrapped_cache_order << cache_key

            while @wrapped_cache_order.length > MAX_WRAPPED_CACHE_SIZE
              oldest = @wrapped_cache_order.shift
              @wrapped_cache.delete(oldest)
            end
          end
        end
      end
    end
  end
end

require_relative 'formatting_service/line_assembler'
require_relative 'formatting_service/plain_lines_builder'
