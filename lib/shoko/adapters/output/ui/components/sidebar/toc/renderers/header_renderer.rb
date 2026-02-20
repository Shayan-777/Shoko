# frozen_string_literal: true

module Shoko
  module Adapters::Output::Ui::Components
    module Sidebar
      # Renders header with title and entry count.
      class HeaderRenderer
        include Adapters::Output::Ui::Constants::Ui

        def initialize(context)
          @context = context
        end

        def render
          writer = HeaderWriter.new(@context)
          writer.write_title(title_content)
          writer.write_subtitle(subtitle_content) if should_show_subtitle?
          writer.write_divider

          @context.metrics.y + 2
        end

        private

        def title_content
          TitleExtractor.new(@context.document, @context.text_metrics).extract
        end

        def subtitle_content
          SubtitleFormatter.new(@context.entries.count, @context.text_metrics).format
        end

        def should_show_subtitle?
          subtitle_width = @context.text_metrics.visible_length(subtitle_content.plain)
          @context.metrics.width > subtitle_width + 2
        end
      end

      # Extracts and formats title from document.
      class TitleExtractor
        DEFAULT_TITLE = 'CONTENTS'

        def initialize(document, text_metrics)
          @document = NullDocument.wrap(document)
          @text_metrics = text_metrics
        end

        def extract
          title = extract_title_text
          return default_content if title.empty?

          TitleContent.new(title.strip.upcase, @text_metrics)
        end

        private

        def default_content
          @default_content ||= TitleContent.new(DEFAULT_TITLE, @text_metrics)
        end

        def extract_title_text
          metadata_title = @document.metadata.fetch(:title, nil)
          metadata_title || @document.title || ''
        end
      end

      # Represents styled title content.
      class TitleContent
        include Adapters::Output::Ui::Constants::Ui

        attr_reader :plain

        def initialize(plain_text, text_metrics)
          @plain = plain_text
          @text_metrics = text_metrics
        end

        def styled
          "#{Terminal::ANSI::BOLD}#{COLOR_TEXT_ACCENT}#{@plain}#{Terminal::ANSI::RESET}"
        end

        def width
          @text_metrics.visible_length(@plain)
        end
      end

      # Formats subtitle with entry count.
      class SubtitleFormatter
        def initialize(count, text_metrics)
          @count = count
          @text_metrics = text_metrics
        end

        def format
          SubtitleContent.new("#{@count} entries", @text_metrics)
        end
      end

      # Represents styled subtitle content.
      class SubtitleContent
        include Adapters::Output::Ui::Constants::Ui

        attr_reader :plain

        def initialize(plain_text, text_metrics)
          @plain = plain_text
          @text_metrics = text_metrics
        end

        def styled
          "#{COLOR_TEXT_DIM}#{@plain}#{Terminal::ANSI::RESET}"
        end

        def width
          @text_metrics.visible_length(@plain)
        end
      end

      # Writes header components to surface.
      class HeaderWriter
        include Adapters::Output::Ui::Constants::Ui

        def initialize(context)
          @context = context
          @metrics = context.metrics
          @last_title_width = 0
        end

        def write_title(title_content)
          @context.write(y_pos, x_pos + 1, title_content.styled)
          @last_title_width = title_content.width
        end

        def write_subtitle(subtitle_content)
          col = calculate_subtitle_column(subtitle_content)
          @context.write(y_pos, col, subtitle_content.styled)
        end

        def write_divider
          width = [@metrics.width - 2, 0].max
          divider = "#{COLOR_TEXT_DIM}#{'─' * width}#{Terminal::ANSI::RESET}"
          @context.write(y_pos + 1, x_pos + 1, divider)
          write_right_junction
        end

        private

        def calculate_subtitle_column(subtitle_content)
          min_col = x_pos + 1 + @last_title_width + 2
          right_col = x_pos + @metrics.width - subtitle_content.width - 1
          [right_col, min_col].max
        end

        def y_pos
          @metrics.y
        end

        def x_pos
          @metrics.x
        end

        def write_right_junction
          junction_col = x_pos + @metrics.width - 1
          return if junction_col < x_pos

          glyph = "#{COLOR_TEXT_DIM}┤#{Terminal::ANSI::RESET}"
          @context.write(y_pos + 1, junction_col, glyph)
        end
      end
    end
  end
end
