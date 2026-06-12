# frozen_string_literal: true

require_relative '../../components/render_style'
require_relative '../../constants/highlighting'
require 'shoko/application/ports/outbound/formatting/display_line'
require 'shoko/core/models/block_type'
require 'shoko/shared/terminal/text_metrics'
require 'shoko/application/ports/outbound/runtime_config'
require_relative 'inline_segment_highlighter'
require_relative 'config_helpers'

module Shoko
  module Adapters
    module Ui
      module Components
        module Reading
          # Composes the plain and ANSI-styled text for a renderable line.
          class LineContentComposer
            ComposeOptions = Data.define(
              :highlight_quotes,
              :highlight_keywords,
              :hover_signature,
              :line_offset,
              :hovered_inline_link
            )
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
              unless runtime_config.is_a?(Shoko::Application::Ports::Outbound::RuntimeConfig)
                raise ArgumentError, 'runtime_config must implement Application::Ports::Outbound::RuntimeConfig'
              end

              @runtime_config = runtime_config
            end

            def compose(line, width, config_store, line_offset: nil, hovered_inline_link: nil)
              with_runtime_config do
                width_i = width.to_i
                return ['', ''] if width_i <= 0

                options = compose_options(config_store,
                                          line_offset: line_offset,
                                          hovered_inline_link: hovered_inline_link)
                fetch_or_compose(line, width_i, options)
              end
            end

            # Hover-link helpers for splitting and styling inline-link segments.
            HoverLink = Data.define(:line_offset, :start_char, :end_char, :href)

            private

            def with_runtime_config(&)
              return yield unless @runtime_config

              self.class.with_runtime_config(config: @runtime_config, &)
            end

            def display_line?(line)
              line.is_a?(Shoko::Application::Ports::Outbound::Formatting::DisplayLine)
            end

            def compose_options(config_store, line_offset:, hovered_inline_link:)
              ComposeOptions.new(
                highlight_quotes: ConfigHelpers.highlight_quotes?(config_store),
                highlight_keywords: ConfigHelpers.highlight_keywords?(config_store),
                hover_signature: hover_signature_for(hovered_inline_link, line_offset),
                line_offset: line_offset,
                hovered_inline_link: hovered_inline_link
              )
            end

            def fetch_or_compose(line, width, options)
              cache_key = compose_cache_key(line, width, options)
              cached = fetch_cached_compose(cache_key)
              return cached unless cached.nil?

              cache_compose_result(cache_key, uncached_compose(line, width, options))
            end

            def uncached_compose(line, width, options)
              return compose_display_line(line, width, options) if display_line?(line)

              compose_plain_line(line, width, options)
            end

            def compose_plain_line(line, width, options)
              text = Shoko::Shared::Terminal::TextMetrics.truncate_to(line.to_s, width)
              text = highlight_keywords(text) if options.highlight_keywords
              text = highlight_quotes(text) if options.highlight_quotes
              plain = Shoko::Shared::Terminal::TextMetrics.strip_ansi(text)
              [plain, Shoko::Adapters::Ui::Components::RenderStyle.primary(text)]
            end

            def compose_display_line(line, width, options)
              metadata = display_line_metadata(line, options.highlight_quotes)
              block_type = metadata[:block_type]
              segments = highlighted_segments(line, block_type, options)
              segments = apply_hover_link_style(
                segments,
                line_offset: options.line_offset,
                hovered_inline_link: options.hovered_inline_link
              )
              build_from_segments(line, segments, width, metadata)
            end

            def highlighted_segments(line, block_type, options)
              InlineSegmentHighlighter.apply(
                Array(line.segments),
                block_type: block_type,
                highlight_quotes: options.highlight_quotes,
                highlight_keywords: options.highlight_keywords
              )
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
                styled << Shoko::Adapters::Ui::Components::RenderStyle.styled_segment(chunk,
                                                                                      segment.styles || {},
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
                quote_color + Shoko::Shared::Terminal::Ansi::ITALIC + match +
                  Shoko::Shared::Terminal::Ansi::RESET + base
              end
            end

            def canonical_block_type(metadata)
              raw = metadata[:block_type]
              Shoko::Core::Models::BlockType.canonical(raw) || raw
            end

            def symbolize_hash(value)
              return {} unless value.is_a?(Hash)

              value.transform_keys do |key|
                key.is_a?(String) ? key.to_sym : key
              end
            end

            # Cache helpers for line composition results.
            def compose_cache_key(line, width, options)
              return nil unless self.class.compose_cache_enabled?

              cache_key_for(line, width, options) << Shoko::Adapters::Ui::Components::RenderStyle.palette.object_id
            end

            def cache_key_for(line, width, options)
              return display_line_cache_key(line, width, options) if display_line?(line)

              plain_line_cache_key(line, width, options)
            end

            def display_line_cache_key(line, width, options)
              metadata = line.metadata || {}
              text = line.text.to_s
              [
                :display_line,
                line.object_id,
                line.segments.object_id,
                text.hash,
                text.bytesize,
                canonical_block_type(metadata),
                width,
                options.highlight_quotes,
                options.highlight_keywords,
                options.hover_signature,
              ]
            end

            def plain_line_cache_key(line, width, options)
              text = line.to_s
              [
                :plain_line,
                text.hash,
                text.bytesize,
                width,
                options.highlight_quotes,
                options.highlight_keywords,
              ]
            end

            def fetch_cached_compose(key)
              return nil unless key && self.class.compose_cache_enabled?

              compose_cache_store[key]
            end

            def cache_compose_result(key, result)
              return result unless key && self.class.compose_cache_enabled?

              frozen_result = freeze_compose_result(result)
              track_compose_cache_key(key)
              compose_cache_store[key] = frozen_result
              frozen_result
            end

            def freeze_compose_result(result)
              plain, styled = result
              [plain.to_s.freeze, styled.to_s.freeze].freeze
            end

            def track_compose_cache_key(key)
              return if compose_cache_store.key?(key)

              compose_cache_order << key
              prune_compose_cache if compose_cache_order.length > self.class::COMPOSE_CACHE_LIMIT
            end

            def prune_compose_cache
              oldest = compose_cache_order.shift
              compose_cache_store.delete(oldest)
            end

            def compose_cache_store
              Thread.current[self.class::COMPOSE_CACHE_KEY] ||= {}
            end

            def compose_cache_order
              Thread.current[self.class::COMPOSE_CACHE_ORDER_KEY] ||= []
            end

            def hover_signature_for(hovered_inline_link, line_offset)
              hover = active_hover_link(hovered_inline_link, line_offset)
              hover && [hover.line_offset, hover.start_char, hover.end_char, hover.href]
            end

            def apply_hover_link_style(segments, line_offset:, hovered_inline_link:)
              hover = active_hover_link(hovered_inline_link, line_offset)
              return segments unless hover

              cursor = 0
              segments.each_with_object([]) do |segment, output|
                text = segment&.text.to_s
                next if text.empty?

                output.concat(split_hovered_segment(segment, text, seg_start: cursor, hover: hover))
                cursor += text.length
              end
            end

            def active_hover_link(hovered_inline_link, line_offset)
              hover = normalize_hovered_inline_link(hovered_inline_link)
              return nil unless hover
              return nil unless line_offset.to_i == hover.line_offset

              hover
            end

            def split_hovered_segment(segment, text, seg_start:, hover:)
              seg_end = seg_start + text.length
              hover_boundaries(seg_start, seg_end, hover).each_cons(2).filter_map do |piece_start, piece_end|
                hovered_segment_piece(
                  piece_start: piece_start,
                  piece_end: piece_end,
                  seg_start: seg_start,
                  text: text,
                  styles: segment.styles || {},
                  hover: hover
                )
              end
            end

            def hover_boundaries(seg_start, seg_end, hover)
              [seg_start, seg_end, hover.start_char, hover.end_char].grep(seg_start..seg_end).uniq.sort
            end

            def hovered_segment_piece(piece_start:, piece_end:, seg_start:, text:, styles:, hover:)
              return nil if piece_end <= piece_start

              piece = text[(piece_start - seg_start)...(piece_end - seg_start)].to_s
              return nil if piece.empty?

              Shoko::Core::Models::TextSegment.new(
                text: piece,
                styles: hover_styles(styles, hover, piece_start, piece_end)
              )
            end

            def hover_styles(styles, hover, piece_start, piece_end)
              return styles unless hover_overlap?(hover, piece_start, piece_end)
              return styles unless link_matches_hover?(styles, hover.href)

              styles.merge(link_hover: true)
            end

            def hover_overlap?(hover, piece_start, piece_end)
              piece_start < hover.end_char && piece_end > hover.start_char
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

              HoverLink.new(
                line_offset: normalized[:line_offset].to_i,
                start_char: start_char,
                end_char: end_char,
                href: href
              )
            end
          end
        end
      end
    end
  end
end
