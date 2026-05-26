# frozen_string_literal: true

require_relative '../../components/render_style'
require_relative '../../constants/highlighting'
require_relative '../../../../core/models/content_block'
require_relative '../../../../core/models/block_type'
require_relative '../../../../shared/terminal/text_metrics'
require_relative '../../../../application/ports/outbound/runtime_config'
require_relative 'inline_segment_highlighter'
require_relative 'config_helpers'
require_relative 'line_content_composer/cache_support'
require_relative 'line_content_composer/hover_link_support'

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

            include LineContentComposerCacheSupport
            include LineContentComposerHoverLinkSupport

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

            private

            def with_runtime_config(&)
              return yield unless @runtime_config

              self.class.with_runtime_config(config: @runtime_config, &)
            end

            def display_line?(line)
              line.is_a?(Shoko::Core::Models::DisplayLine)
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
          end
        end
      end
    end
  end
end
