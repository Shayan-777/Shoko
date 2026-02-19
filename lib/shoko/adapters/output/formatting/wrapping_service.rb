# frozen_string_literal: true

require_relative '../../base_adapter'
require_relative '../../runtime/runtime_config_provider'

module Shoko
  module Adapters
    module Output
      module Formatting
        # Service responsible for wrapping chapter lines to a column width.
        # Uses an adapter-local chapter cache to avoid recomputation across frames.
        class WrappingService < Shoko::Adapters::BaseAdapter
          WINDOW_CACHE_LIMIT = 200

          # Adapter-local wrapped-lines cache keyed by [chapter_index, width] and input identity.
          class ChapterCache
            def initialize(text_metrics:)
              raise ArgumentError, 'text_metrics is required' unless text_metrics

              @text_metrics = text_metrics
              @wrapped_cache = {}
              @cache_key_memo = {}
            end

            def get_wrapped_lines(chapter_index, lines, width)
              cache_key = "#{chapter_index}_#{width}"
              cached = @wrapped_cache[cache_key]
              memo_id = @cache_key_memo[cache_key]
              return cached if cached && memo_id == lines.object_id

              wrapped = wrap_lines_internal(lines, width)
              @wrapped_cache[cache_key] = wrapped
              @cache_key_memo[cache_key] = lines.object_id
              wrapped
            end

            def clear_cache_for_width(width)
              @wrapped_cache.delete_if { |key, _| key.end_with?("_#{width}") }
            end

            private

            def wrap_lines_internal(lines, width)
              return [] if lines.nil? || width < 1

              wrapped = []
              lines.each do |line|
                next if line.nil?

                if line.strip.empty?
                  wrapped << ''
                else
                  segments = @text_metrics.wrap_plain_text(line, width)
                  wrapped.concat(segments)
                end
              end
              wrapped
            end
          end

          # @param text_metrics [Object] Text metrics for measuring/wrapping
          # @param async_executor [Object] Executor for background work
          # @param session_context [Object, nil] Optional reader session context
          # @param config_reader [Object, nil] Optional config reader port
          # @param runtime_config [Core::Ports::RuntimeConfig, nil] Optional runtime configuration
          # @param formatting_service_provider [Proc, nil] Optional callable returning formatting service
          # @param document_provider [Proc, nil] Optional callable returning current document
          # @param logger [Object, nil] Optional logger
          def initialize(text_metrics:, async_executor:, session_context: nil, config_reader: nil,
                         runtime_config: nil, formatting_service_provider: nil, document_provider: nil, logger: nil)
            super(logger: logger)
            @text_metrics = text_metrics
            @async_executor = async_executor
            @session_context = session_context
            @config_reader = config_reader
            @runtime_config = runtime_config || Shoko::Adapters::Runtime::RuntimeConfigProvider.runtime_config
            @formatting_service_provider = formatting_service_provider
            @document_provider = document_provider
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
            rescue StandardError
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
            ChapterCache.new(
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
            formatting = formatting_service
            return unless formatting

            document ||= current_document
            return unless document

            lines = formatting.wrap_window(document, chapter_index, width, offset: offset, length: length)
            return unless lines && !lines.empty?

            lines.map { |line| line.respond_to?(:text) ? line.text : line }
          rescue StandardError
            nil
          end

          def current_document
            session_document = @session_context&.document
            return session_document if session_document

            return nil unless @document_provider.respond_to?(:call)

            @document_provider.call
          rescue StandardError
            nil
          end

          def enqueue_prefetch(chapter_index, col_width, prefetch_start, prefetch_len, lines)
            job = lambda do
              prefetch_windows(lines, chapter_index, col_width, prefetch_start, prefetch_len)
            end
            @async_executor.submit(&job)
          rescue StandardError
            # ignore background failures
          end

          def formatting_service
            return nil unless @formatting_service_provider.respond_to?(:call)

            @formatting_service_provider.call
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
