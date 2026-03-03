# frozen_string_literal: true

require_relative '../../base_adapter'
require_relative '../../../core/ports/outbound/line_wrapper'
require_relative '../../../core/ports/outbound/runtime_config'
require_relative '../../../core/ports/outbound/chapter_formatter'
require_relative '../../../core/ports/outbound/reader_launch_state'
require_relative '../../../core/models/content_block'
require_relative '../../../core/services/pagination/internal/chapter_cache'

module Shoko
  module Adapters
    module Output
      module Formatting
        # Service responsible for wrapping chapter lines to a column width.
        # Uses an adapter-local chapter cache to avoid recomputation across frames.
        class WrappingService < Shoko::Adapters::BaseAdapter
          include Shoko::Core::Ports::Outbound::LineWrapper

          WINDOW_CACHE_LIMIT = 200

          # @param text_metrics [Object] Text metrics for measuring/wrapping
          # @param async_executor [Object] Executor for background work
          # @param reader_launch_state [Core::Ports::Outbound::ReaderLaunchState]
          # @param config_reader [Object, nil] Optional config reader port
          # @param runtime_config [Core::Ports::Outbound::RuntimeConfig] Runtime configuration
          # @param formatting_service [Core::Ports::Outbound::ChapterFormatter] Formatting service
          # @param logger [Object, nil] Optional logger
          def initialize(text_metrics:, async_executor:, reader_launch_state:, config_reader: nil,
                         runtime_config:, formatting_service:, logger: nil)
            super(logger: logger)
            unless reader_launch_state.is_a?(Shoko::Core::Ports::Outbound::ReaderLaunchState)
              raise ArgumentError, 'reader_launch_state must implement Core::Ports::Outbound::ReaderLaunchState'
            end
            unless runtime_config.is_a?(Shoko::Core::Ports::Outbound::RuntimeConfig)
              raise ArgumentError, 'runtime_config must implement Core::Ports::Outbound::RuntimeConfig'
            end
            unless formatting_service.is_a?(Shoko::Core::Ports::Outbound::ChapterFormatter)
              raise ArgumentError, 'formatting_service must implement Core::Ports::Outbound::ChapterFormatter'
            end

            @text_metrics = text_metrics
            @async_executor = async_executor
            @reader_launch_state = reader_launch_state
            @config_reader = config_reader
            @runtime_config = runtime_config
            @formatting_service = formatting_service
            @chapter_cache = build_chapter_cache
            @window_cache = Hash.new { |h, k| h[k] = { store: {}, order: [] } }
          end

          # Wrap raw lines for a chapter to the given width.
          # Falls back to a local wrapper if cache is unavailable.
          #
          # @param lines [Array<String>] raw chapter lines
          # @param chapter_index [Integer] chapter index for caching keying
          # @param width [Integer] column width
          # @return [Array<String>] wrapped lines
          def wrap_lines(lines, chapter_index, width, document: nil)
            return [] if lines.nil? || width.to_i < 10

            formatted = fetch_formatted_lines(chapter_index, width, 0, lines.length, document: document)
            return formatted if formatted

            @chapter_cache.get_wrapped_lines(chapter_index, lines, width)
          end

          # Wrap only a window of text sufficient for immediate display.
          # This avoids wrapping the entire chapter on first render.
          #
          # @param lines [Array<String>] raw chapter lines
          # @param chapter_index [Integer] chapter index (for caching semantics if needed)
          # @param width [Integer] column width
          # @param start [Integer] wrapped-lines start offset
          # @param length [Integer] number of wrapped lines to return
          # @return [Array<String>] slice of wrapped lines covering the requested window
          def wrap_window(lines, chapter_index, width, start, length, document: nil)
            width_i = width.to_i
            length_i = length.to_i
            start_i = [start.to_i, 0].max
            return [] if lines.nil? || width_i <= 0 || length_i <= 0

            formatted = fetch_formatted_lines(chapter_index, width_i, start_i, length_i, document: document)
            return formatted if formatted

            target_end = start_i + length_i - 1
            key = [lines.object_id, chapter_index, width_i]
            cached = cached_window_for(key, start_i, length_i)
            return cached if cached

            wrapped = []

            lines.each do |line|
              break if wrapped.length >= (target_end + 1)

              next if line.nil?

              if line.strip.empty?
                wrapped << ''
                next
              end

              segments = @text_metrics.wrap_plain_text(line, width_i)
              wrapped.concat(segments)
            end

            return [] if start_i >= wrapped.length

            slice = wrapped[start_i, length_i] || []
            cache_put(key, [start_i, length_i], slice)
            slice
          end

          def prefetch_windows(lines, chapter_index, width, start, length)
            wrap_window(lines, chapter_index, width, start, length)
          end

          # Wrap the visible window and prefetch ±N pages around it in the background.
          # This centralizes the behavior that was previously embedded in ReaderController.
          #
          # @param doc [Object] document responding to #get_chapter(index)
          # @param chapter_index [Integer]
          # @param col_width [Integer]
          # @param offset [Integer] wrapped-line offset
          # @param display_height [Integer] lines per page
          # @param pre_pages [Integer,nil] optional number of pages to prefetch; defaults from config
          # @return [Array<String>] visible wrapped lines for the requested window
          def fetch_window_and_prefetch(doc, chapter_index, col_width, offset, display_height,
                                        pre_pages = nil)
            return [] unless doc && display_height.to_i.positive?

            chapter = doc.get_chapter(chapter_index)
            return [] unless chapter

            lines = chapter.lines || []
            start_i = [offset.to_i, 0].max
            length_i = display_height.to_i

            visible = wrap_window(lines, chapter_index, col_width, start_i, length_i, document: doc)

            begin
              pages = pre_pages
              pages = @config_reader&.prefetch_pages if pages.nil?
              pages = pages.nil? ? 20 : pages.to_i
              pages = pages.clamp(0, 200)
              window = pages * length_i
              prefetch_start = [start_i - window, 0].max
              prefetch_end   = start_i + window + (length_i - 1)
              prefetch_len   = prefetch_end - prefetch_start + 1
              enqueue_prefetch(chapter_index, col_width, prefetch_start, prefetch_len, lines)
            rescue Shoko::Error
              # best-effort prefetch
            end

            visible
          end

          # Clear all cached wrapped lines
          def clear_cache
            @chapter_cache = build_chapter_cache
            @window_cache.clear
          end

          # Clear cache entries for a given width
          def clear_cache_for_width(width)
            width_i = width.to_i
            @chapter_cache.clear_cache_for_width(width_i)
            @window_cache.delete_if do |key, _|
              key.is_a?(Array) ? key[2] == width_i : key.to_s.end_with?("_#{width_i}")
            end
          end

          private

          def build_chapter_cache
            Shoko::Core::Services::Pagination::Internal::ChapterCache.new(
              text_metrics: @text_metrics
            )
          end

          def cache_put(key, subkey, value)
            entry = @window_cache[key]
            store = entry[:store]
            order = entry[:order]
            unless store.key?(subkey)
              order << subkey
              if order.length > WINDOW_CACHE_LIMIT
                oldest = order.shift
                store.delete(oldest)
              end
            end
            store[subkey] = value
          end

          def cached_window_for(key, start_i, length_i)
            store = @window_cache[key][:store]
            exact = store[[start_i, length_i]]
            return exact unless exact.nil?
            return nil unless window_range_cache_enabled?

            covered_window_slice(store, start_i, length_i)
          end

          def covered_window_slice(store, start_i, length_i)
            requested_end = start_i + length_i - 1
            store.each do |(cached_start, cached_length), cached_values|
              cached_end = cached_start + cached_length - 1
              next if cached_start > start_i || cached_end < requested_end

              offset = start_i - cached_start
              return cached_values[offset, length_i] || []
            end
            nil
          end

          def window_range_cache_enabled?
            !@runtime_config.wrapping_window_range_cache_disabled?
          end

          def fetch_formatted_lines(chapter_index, width, offset, length, document: nil)
            document ||= current_document
            return unless document

            lines = @formatting_service.wrap_window(document, chapter_index, width, offset: offset, length: length)
            return unless lines && !lines.empty?

            lines.map { |line| line.is_a?(Shoko::Core::Models::DisplayLine) ? line.text : line }
          rescue Shoko::Error
            raise
          end

          def current_document
            @reader_launch_state.preloaded_document
          rescue Shoko::Error
            raise
          end

          def enqueue_prefetch(chapter_index, col_width, prefetch_start, prefetch_len, lines)
            job = lambda do
              prefetch_windows(lines, chapter_index, col_width, prefetch_start, prefetch_len)
            end
            @async_executor.submit(&job)
          rescue Shoko::Error
            # ignore background failures
          end

        end
      end
    end
  end
end
