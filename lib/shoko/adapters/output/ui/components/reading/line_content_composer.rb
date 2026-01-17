# frozen_string_literal: true

require_relative '../render_style'
require_relative '../../../terminal/text_metrics'
require_relative 'inline_segment_highlighter'
require_relative 'config_helpers'

module Shoko
  module Adapters::Output::Ui::Components
    module Reading
      # Composes the plain and ANSI-styled text for a renderable line.
      class LineContentComposer
        def compose(line, width, config_store)
          width_i = width.to_i
          return ['', ''] if width_i <= 0

          return compose_display_line(line, width_i, config_store) if display_line?(line)

          compose_plain_line(line, width_i, config_store)
        end

        private

        def display_line?(line)
          line.respond_to?(:segments) && line.respond_to?(:text)
        end

        def compose_plain_line(line, width, store)
          text = Shoko::Adapters::Output::Terminal::TextMetrics.truncate_to(line.to_s, width)
          return [text, Shoko::Adapters::Output::Ui::Components::RenderStyle.primary(text)] unless store

          text = highlight_keywords(text) if ConfigHelpers.highlight_keywords?(store)
          text = highlight_quotes(text) if ConfigHelpers.highlight_quotes?(store)
          [Shoko::Adapters::Output::Terminal::TextMetrics.strip_ansi(text), Shoko::Adapters::Output::Ui::Components::RenderStyle.primary(text)]
        end

        def compose_display_line(line, width, store)
          highlight_quotes = ConfigHelpers.highlight_quotes?(store)
          highlight_keywords = ConfigHelpers.highlight_keywords?(store)

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
