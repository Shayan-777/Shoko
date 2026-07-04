# frozen_string_literal: true

require_relative '../../base_adapter'
require 'shoko/application/ports/outbound/line_wrapper'
require 'shoko/application/ports/outbound/runtime_config'
require 'shoko/application/ports/outbound/chapter_formatter'
require 'shoko/application/ports/outbound/formatting/display_line'

module Shoko
  module Adapters
    module Output
      module Formatting
        # Service responsible for wrapping chapter lines to a column width.
        # Uses an adapter-local chapter cache to avoid recomputation across frames.
        class WrappingService < Shoko::Adapters::BaseAdapter
          include Shoko::Application::Ports::Outbound::LineWrapper

          WINDOW_CACHE_LIMIT = 200

          # @param text_metrics [Object] Text metrics for measuring/wrapping
          # @param async_executor [Object] Executor for background work
          # @param config_reader [Object, nil] Optional config reader port
          # @param runtime_config [Application::Ports::Outbound::RuntimeConfig] Runtime configuration
          # @param formatting_service [Application::Ports::Outbound::ChapterFormatter] Formatting service
          # @param chapter_cache_factory [#call] Factory invoked as call(text_metrics:)
          # @param logger [Object, nil] Optional logger
          def initialize(text_metrics:, async_executor:, runtime_config:, formatting_service:,
                         chapter_cache_factory:, config_reader: nil, logger: nil)
            super(logger: logger)
            unless runtime_config.is_a?(Shoko::Application::Ports::Outbound::RuntimeConfig)
              raise ArgumentError, 'runtime_config must implement Application::Ports::Outbound::RuntimeConfig'
            end
            unless formatting_service.is_a?(Shoko::Application::Ports::Outbound::ChapterFormatter)
              raise ArgumentError, 'formatting_service must implement Application::Ports::Outbound::ChapterFormatter'
            end
            unless chapter_cache_factory.respond_to?(:call)
              raise ArgumentError, 'chapter_cache_factory must respond to #call'
            end

            @text_metrics = text_metrics
            @async_executor = async_executor
            @config_reader = config_reader
            @runtime_config = runtime_config
            @formatting_service = formatting_service
            @chapter_cache_factory = chapter_cache_factory
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
          def wrap_window(*request_args, document: nil)
            request = WindowRequest.build(*request_args, document: document)
            return [] unless request.valid?

            formatted = fetch_formatted_lines(
              request.chapter_index,
              request.width,
              request.start,
              request.length,
              document: request.document
            )
            return formatted if formatted

            cached = cached_window_for(request.cache_key, request.start, request.length)
            return cached if cached

            slice = wrapped_window_slice(request)
            cache_put(request.cache_key, request.cache_subkey, slice)
            slice
          end

          def prefetch_windows(*request_args)
            wrap_window(*request_args)
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
          def fetch_window_and_prefetch(*request_args)
            request = FetchRequest.build(*request_args)
            return [] unless request.valid?

            chapter = request.document.get_chapter(request.chapter_index)
            return [] unless chapter

            lines = plain_lines_for_chapter(request.document, request.chapter_index, chapter)

            visible = visible_window_for(request, lines)
            enqueue_prefetch(request, lines)
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

          # Source plain lines via the formatter port (which owns parsing)
          # instead of reading the now-deprecated `chapter.lines` back-write.
          # Falls back to `chapter.lines` when the importer set them directly
          # at import time.
          def plain_lines_for_chapter(document, chapter_index, chapter)
            lines = @formatting_service.plain_lines_for(document, chapter_index)
            return Array(lines) unless lines.nil? || lines.empty?

            Array(chapter.lines)
          end

          def wrapped_window_slice(request)
            wrapped = collect_wrapped_window_lines(request)
            return [] if request.start >= wrapped.length

            wrapped[request.start, request.length] || []
          end

          def collect_wrapped_window_lines(request)
            wrapped = []

            Array(request.lines).each do |line|
              break if wrapped.length > request.target_end

              append_wrapped_line(wrapped, line, request.width)
            end

            wrapped
          end

          def append_wrapped_line(wrapped, line, width)
            return if line.nil?

            if line.strip.empty?
              wrapped << ''
              return
            end

            wrapped.concat(@text_metrics.wrap_plain_text(line, width))
          end

          def visible_window_for(request, lines)
            wrap_window(
              lines,
              request.chapter_index,
              request.col_width,
              request.offset,
              request.window_length,
              document: request.document
            )
          end

          def build_chapter_cache
            @chapter_cache_factory.call(text_metrics: @text_metrics)
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
            return unless document

            lines = @formatting_service.wrap_window(document, chapter_index, width, offset: offset, length: length)
            return unless lines && !lines.empty?

            lines.map { |line| line.is_a?(Shoko::Application::Ports::Outbound::Formatting::DisplayLine) ? line.text : line }
          end

          def enqueue_prefetch(request, lines)
            prefetch_request = prefetch_window_request(request, lines)
            return unless prefetch_request

            job = lambda do
              prefetch_windows(
                prefetch_request.lines,
                prefetch_request.chapter_index,
                prefetch_request.width,
                prefetch_request.start,
                prefetch_request.length
              )
            end
            @async_executor.submit(&job)
          # resilient-boundary
          rescue StandardError => e
            swallow_prefetch_submit_error(e)
          end

          # Prefetch is opportunistic: a submit refused by a shutting-down
          # worker (WorkerStoppedError is a plain StandardError, not a
          # Shoko::Error) must never break the render path that scheduled it.
          def swallow_prefetch_submit_error(error)
            logger&.debug('wrapping_service.prefetch_submit_failed',
                          error: error.class.name, message: error.message)
          end

          def prefetch_window_request(request, lines)
            pages = request.resolved_prefetch_pages(@config_reader)
            window = pages * request.window_length
            prefetch_start = [request.offset - window, 0].max
            prefetch_end = request.offset + window + (request.window_length - 1)
            prefetch_length = prefetch_end - prefetch_start + 1

            WindowRequest.new(
              lines: lines,
              chapter_index: request.chapter_index,
              width: request.col_width,
              start: prefetch_start,
              length: prefetch_length,
              document: request.document
            )
          end
        end
      end
    end
  end
end

require_relative 'wrapping_service/window_request'
require_relative 'wrapping_service/fetch_request'
