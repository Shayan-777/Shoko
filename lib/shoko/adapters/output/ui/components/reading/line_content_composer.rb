# frozen_string_literal: true

require_relative '../render_style'
require_relative '../../../terminal/text_metrics'
require_relative '../../../../runtime/runtime_config_provider'
require_relative 'inline_segment_highlighter'
require_relative 'config_helpers'

module Shoko
  module Adapters::Output::Ui::Components
    module Reading
      # Composes the plain and ANSI-styled text for a renderable line.
      class LineContentComposer
        COMPOSE_CACHE_LIMIT = 20_000
        COMPOSE_CACHE_KEY = :shoko_line_content_compose_cache
        COMPOSE_CACHE_ORDER_KEY = :shoko_line_content_compose_cache_order
        COMPOSE_CACHE_ENABLED_KEY = :shoko_line_content_compose_cache_enabled

        class << self
          def with_compose_cache(enabled:)
            previous = Thread.current[COMPOSE_CACHE_ENABLED_KEY]
            Thread.current[COMPOSE_CACHE_ENABLED_KEY] = enabled ? true : false
            yield
          ensure
            Thread.current[COMPOSE_CACHE_ENABLED_KEY] = previous
          end

          def compose_cache_enabled?
            override = Thread.current[COMPOSE_CACHE_ENABLED_KEY]
            return override unless override.nil?

            !runtime_config.line_content_compose_cache_disabled?
          end

          def clear_compose_cache
            Thread.current[COMPOSE_CACHE_KEY] = {}
            Thread.current[COMPOSE_CACHE_ORDER_KEY] = []
          end

          def runtime_config
            Shoko::Adapters::Runtime::RuntimeConfigProvider.runtime_config
          rescue StandardError
            Shoko::Adapters::Runtime::EnvRuntimeConfigAdapter.new
          end
        end

        def compose(line, width, config_store)
          width_i = width.to_i
          return ['', ''] if width_i <= 0

          highlight_quotes = ConfigHelpers.highlight_quotes?(config_store)
          highlight_keywords = ConfigHelpers.highlight_keywords?(config_store)
          cache_key = compose_cache_key(line, width_i, highlight_quotes, highlight_keywords)
          cached = fetch_cached_compose(cache_key)
          return cached unless cached.nil?

          result = if display_line?(line)
                     compose_display_line(
                       line,
                       width_i,
                       highlight_quotes: highlight_quotes,
                       highlight_keywords: highlight_keywords
                     )
                   else
                     compose_plain_line(
                       line,
                       width_i,
                       highlight_quotes: highlight_quotes,
                       highlight_keywords: highlight_keywords
                     )
                   end

          cache_compose_result(cache_key, result)
        end

        private

        def display_line?(line)
          line.respond_to?(:segments) && line.respond_to?(:text)
        end

        def compose_plain_line(line, width, highlight_quotes:, highlight_keywords:)
          text = Shoko::Adapters::Output::Terminal::TextMetrics.truncate_to(line.to_s, width)
          text = highlight_keywords(text) if highlight_keywords
          text = highlight_quotes(text) if highlight_quotes
          [Shoko::Adapters::Output::Terminal::TextMetrics.strip_ansi(text), Shoko::Adapters::Output::Ui::Components::RenderStyle.primary(text)]
        end

        def compose_display_line(line, width, highlight_quotes:, highlight_keywords:)
          metadata = display_line_metadata(line, highlight_quotes)
          block_type = metadata[:block_type] || metadata['block_type']
          segments = InlineSegmentHighlighter.apply(Array(line.segments),
                                                    block_type: block_type,
                                                    highlight_quotes: highlight_quotes,
                                                    highlight_keywords: highlight_keywords)
          build_from_segments(line, segments, width, metadata)
        end

        def display_line_metadata(line, highlight_quotes)
          metadata = (line.metadata || {}).dup
          metadata[:highlight_enabled] = highlight_quotes
          metadata
        end

        def build_from_segments(line, segments, width, metadata)
          plain = +''
          styled = +''
          remaining = width

          segments.each do |segment|
            break if remaining <= 0

            chunk = segment_text_for_width(segment, remaining)
            next if chunk.empty?

            plain << chunk
            styled << Shoko::Adapters::Output::Ui::Components::RenderStyle.styled_segment(chunk, segment.styles || {},
                                                                                          metadata: metadata)
            remaining -= Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(chunk)
          end

          finalize_composed_line(line, width, plain, styled)
        end

        def segment_text_for_width(segment, remaining)
          raw = segment&.text.to_s
          return '' if raw.empty?

          visible_len = Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(raw)
          return raw if visible_len <= remaining

          Shoko::Adapters::Output::Terminal::TextMetrics.truncate_to(raw, remaining)
        end

        def finalize_composed_line(line, width, plain_builder, styled_builder)
          if styled_builder.empty?
            plain_text = plain_builder.empty? ? line.text.to_s[0, width] : plain_builder
            return [plain_text, Shoko::Adapters::Output::Ui::Components::RenderStyle.primary(plain_text)]
          end

          plain_text = plain_builder.empty? ? line.text.to_s[0, width] : plain_builder
          [plain_text, styled_builder]
        end

        def compose_cache_key(line, width, highlight_quotes, highlight_keywords)
          return nil unless self.class.compose_cache_enabled?

          palette_id = Shoko::Adapters::Output::Ui::Components::RenderStyle.palette.object_id
          if display_line?(line)
            metadata = line.metadata || {}
            block_type = metadata[:block_type] || metadata['block_type']
            text = line.text.to_s
            [:display_line, line.object_id, line.segments.object_id, text.hash, text.bytesize,
             block_type, width, highlight_quotes, highlight_keywords, palette_id]
          else
            text = line.to_s
            [:plain_line, text.hash, text.bytesize, width, highlight_quotes, highlight_keywords, palette_id]
          end
        rescue StandardError
          nil
        end

        def fetch_cached_compose(key)
          return nil unless key && self.class.compose_cache_enabled?

          compose_cache_store[key]
        end

        def cache_compose_result(key, result)
          return result unless key && self.class.compose_cache_enabled?

          plain, styled = result
          frozen_result = [plain.to_s.freeze, styled.to_s.freeze].freeze
          store = compose_cache_store
          order = compose_cache_order
          unless store.key?(key)
            order << key
            if order.length > COMPOSE_CACHE_LIMIT
              oldest = order.shift
              store.delete(oldest)
            end
          end
          store[key] = frozen_result
          frozen_result
        rescue StandardError
          result
        end

        def compose_cache_store
          Thread.current[COMPOSE_CACHE_KEY] ||= {}
        end

        def compose_cache_order
          Thread.current[COMPOSE_CACHE_ORDER_KEY] ||= []
        end

        def highlight_keywords(line)
          accent = Shoko::Adapters::Output::Ui::Components::RenderStyle.color(:accent)
          base = Shoko::Adapters::Output::Ui::Components::RenderStyle.color(:primary)
          line.gsub(Shoko::Adapters::Output::Ui::Constants::Highlighting::HIGHLIGHT_PATTERNS) do |match|
            accent + match + Terminal::ANSI::RESET + base
          end
        end

        def highlight_quotes(line)
          quote_color = Shoko::Adapters::Output::Ui::Components::RenderStyle.color(:quote)
          base = Shoko::Adapters::Output::Ui::Components::RenderStyle.color(:primary)
          line.gsub(Shoko::Adapters::Output::Ui::Constants::Highlighting::QUOTE_PATTERNS) do |match|
            quote_color + Terminal::ANSI::ITALIC + match + Terminal::ANSI::RESET + base
          end
        end
      end
    end
  end
end
