# frozen_string_literal: true

require_relative '../../components/render_style'
require_relative '../../constants/highlighting'
require_relative '../../../../core/models/content_block'
require_relative '../../../../core/models/block_type'
require_relative '../../../../shared/terminal/text_metrics'
require_relative '../../../../core/ports/outbound/runtime_config'
require_relative 'inline_segment_highlighter'
require_relative 'config_helpers'

module Shoko
  module Adapters
    module Ui
      module Components
        module Reading
          # Composes the plain and ANSI-styled text for a renderable line.
          class LineContentComposer
            COMPOSE_CACHE_LIMIT = 20_000
            COMPOSE_CACHE_KEY = :shoko_line_content_compose_cache
            COMPOSE_CACHE_ORDER_KEY = :shoko_line_content_compose_cache_order
            COMPOSE_CACHE_ENABLED_KEY = :shoko_line_content_compose_cache_enabled
            RUNTIME_CONFIG_KEY = :shoko_line_content_compose_runtime_config

            class << self
              def with_runtime_config(config:)
                previous = Thread.current[RUNTIME_CONFIG_KEY]
                Thread.current[RUNTIME_CONFIG_KEY] = config if config
                yield
              ensure
                Thread.current[RUNTIME_CONFIG_KEY] = previous
              end

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
                config = Thread.current[RUNTIME_CONFIG_KEY]
                return config if config

                raise Shoko::ConfigurationError, 'LineContentComposer runtime_config is not configured'
              end
            end

            def initialize(runtime_config:)
              unless runtime_config.is_a?(Shoko::Core::Ports::Outbound::RuntimeConfig)
                raise ArgumentError, 'runtime_config must implement Core::Ports::Outbound::RuntimeConfig'
              end

              @runtime_config = runtime_config
            end

            def compose(line, width, config_store, line_offset: nil, hovered_inline_link: nil)
              with_runtime_config do
                width_i = width.to_i
                return ['', ''] if width_i <= 0

                highlight_quotes = ConfigHelpers.highlight_quotes?(config_store)
                highlight_keywords = ConfigHelpers.highlight_keywords?(config_store)
                hover_signature = hover_signature_for(hovered_inline_link, line_offset)
                cache_key = compose_cache_key(line, width_i, highlight_quotes, highlight_keywords, hover_signature)
                cached = fetch_cached_compose(cache_key)
                return cached unless cached.nil?

                result = if display_line?(line)
                           compose_display_line(
                             line,
                             width_i,
                             line_offset: line_offset,
                             hovered_inline_link: hovered_inline_link,
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
            end

            private

            def with_runtime_config(&)
              return yield unless @runtime_config

              self.class.with_runtime_config(config: @runtime_config, &)
            end

            def display_line?(line)
              line.is_a?(Shoko::Core::Models::DisplayLine)
            end

            def compose_plain_line(line, width, highlight_quotes:, highlight_keywords:)
              text = Shoko::Shared::Terminal::TextMetrics.truncate_to(line.to_s, width)
              text = highlight_keywords(text) if highlight_keywords
              text = highlight_quotes(text) if highlight_quotes
              [Shoko::Shared::Terminal::TextMetrics.strip_ansi(text), Shoko::Adapters::Ui::Components::RenderStyle.primary(text)]
            end

            def compose_display_line(line, width, line_offset:, hovered_inline_link:, highlight_quotes:, highlight_keywords:)
              metadata = display_line_metadata(line, highlight_quotes)
              block_type = metadata[:block_type]
              segments = InlineSegmentHighlighter.apply(Array(line.segments),
                                                        block_type: block_type,
                                                        highlight_quotes: highlight_quotes,
                                                        highlight_keywords: highlight_keywords)
              segments = apply_hover_link_style(segments, line_offset: line_offset, hovered_inline_link: hovered_inline_link)
              build_from_segments(line, segments, width, metadata)
            end

            def display_line_metadata(line, highlight_quotes)
              metadata = (line.metadata || {}).dup
              block_type = canonical_block_type(metadata)
              metadata.delete('block_type')
              metadata[:block_type] = block_type if block_type
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
                styled << Shoko::Adapters::Ui::Components::RenderStyle.styled_segment(chunk, segment.styles || {},
                                                                                      metadata: metadata)
                remaining -= Shoko::Shared::Terminal::TextMetrics.visible_length(chunk)
              end

              finalize_composed_line(line, width, plain, styled)
            end

            def segment_text_for_width(segment, remaining)
              raw = segment&.text.to_s
              return '' if raw.empty?

              visible_len = Shoko::Shared::Terminal::TextMetrics.visible_length(raw)
              return raw if visible_len <= remaining

              Shoko::Shared::Terminal::TextMetrics.truncate_to(raw, remaining)
            end

            def finalize_composed_line(line, width, plain_builder, styled_builder)
              if styled_builder.empty?
                plain_text = plain_builder.empty? ? line.text.to_s[0, width] : plain_builder
                return [plain_text, Shoko::Adapters::Ui::Components::RenderStyle.primary(plain_text)]
              end

              plain_text = plain_builder.empty? ? line.text.to_s[0, width] : plain_builder
              [plain_text, styled_builder]
            end

            def compose_cache_key(line, width, highlight_quotes, highlight_keywords, hover_signature)
              return nil unless self.class.compose_cache_enabled?

              palette_id = Shoko::Adapters::Ui::Components::RenderStyle.palette.object_id
              if display_line?(line)
                metadata = line.metadata || {}
                block_type = canonical_block_type(metadata)
                text = line.text.to_s
                [:display_line, line.object_id, line.segments.object_id, text.hash, text.bytesize,
                 block_type, width, highlight_quotes, highlight_keywords, hover_signature, palette_id]
              else
                text = line.to_s
                [:plain_line, text.hash, text.bytesize, width, highlight_quotes, highlight_keywords, palette_id]
              end
            end

            def hover_signature_for(hovered_inline_link, line_offset)
              hover = normalize_hovered_inline_link(hovered_inline_link)
              return nil unless hover
              return nil unless line_offset.to_i == hover[:line_offset]

              [hover[:line_offset], hover[:start_char], hover[:end_char], hover[:href]]
            end

            def apply_hover_link_style(segments, line_offset:, hovered_inline_link:)
              hover = normalize_hovered_inline_link(hovered_inline_link)
              return segments unless hover
              return segments unless line_offset.to_i == hover[:line_offset]

              start_char = hover[:start_char]
              end_char = hover[:end_char]
              href = hover[:href]
              return segments unless end_char > start_char

              output = []
              cursor = 0
              segments.each do |segment|
                text = segment&.text.to_s
                length = text.length
                next if length <= 0

                seg_start = cursor
                seg_end = cursor + length
                cursor = seg_end

                boundaries = [seg_start, seg_end]
                boundaries << start_char if start_char > seg_start && start_char < seg_end
                boundaries << end_char if end_char > seg_start && end_char < seg_end
                boundaries.sort!
                boundaries.uniq!

                boundaries.each_cons(2) do |piece_start, piece_end|
                  next if piece_end <= piece_start

                  piece = text[(piece_start - seg_start)...(piece_end - seg_start)].to_s
                  next if piece.empty?

                  styles = segment.styles || {}
                  hovered_piece = piece_start < end_char && piece_end > start_char
                  piece_styles = if hovered_piece && link_matches_hover?(styles, href)
                                   styles.merge(link_hover: true)
                                 else
                                   styles
                                 end
                  output << Shoko::Core::Models::TextSegment.new(text: piece, styles: piece_styles)
                end
              end

              output
            end

            def link_matches_hover?(styles, hover_href)
              link = styles[:link]
              return false if link.nil?

              link.to_s.strip == hover_href.to_s
            end

            def normalize_hovered_inline_link(value)
              return nil unless value.is_a?(Hash)

              normalized = symbolize_hash(value)
              start_char = normalized[:start_char].to_i
              end_char = normalized[:end_char].to_i
              href = normalized[:href].to_s.strip
              return nil if href.empty? || end_char <= start_char

              {
                line_offset: normalized[:line_offset].to_i,
                start_char: start_char,
                end_char: end_char,
                href: href
              }
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
            end

            def compose_cache_store
              Thread.current[COMPOSE_CACHE_KEY] ||= {}
            end

            def compose_cache_order
              Thread.current[COMPOSE_CACHE_ORDER_KEY] ||= []
            end

            def highlight_keywords(line)
              accent = Shoko::Adapters::Ui::Components::RenderStyle.color(:accent)
              base = Shoko::Adapters::Ui::Components::RenderStyle.color(:primary)
              line.gsub(Shoko::Adapters::Ui::Constants::Highlighting::HIGHLIGHT_PATTERNS) do |match|
                accent + match + Shoko::Shared::Terminal::Ansi::RESET + base
              end
            end

            def highlight_quotes(line)
              quote_color = Shoko::Adapters::Ui::Components::RenderStyle.color(:quote)
              base = Shoko::Adapters::Ui::Components::RenderStyle.color(:primary)
              line.gsub(Shoko::Adapters::Ui::Constants::Highlighting::QUOTE_PATTERNS) do |match|
                quote_color + Shoko::Shared::Terminal::Ansi::ITALIC + match + Shoko::Shared::Terminal::Ansi::RESET + base
              end
            end

            def canonical_block_type(metadata)
              raw = metadata[:block_type]
              Shoko::Core::Models::BlockType.canonical(raw) || raw
            end

            def symbolize_hash(value)
              return {} unless value.is_a?(Hash)

              value.each_with_object({}) do |(key, inner_value), normalized|
                normalized[key.is_a?(String) ? key.to_sym : key] = inner_value
              end
            end
          end
        end
      end
    end
  end
end
