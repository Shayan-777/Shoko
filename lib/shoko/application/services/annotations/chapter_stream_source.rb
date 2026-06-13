# frozen_string_literal: true

require 'shoko/application/ports/outbound/chapter_formatter'
require 'shoko/application/ports/outbound/line_wrapper'
require 'shoko/application/ports/outbound/reader_runtime_context'
require 'shoko/core/models/reader_settings'

module Shoko
  module Application
    module Services
      module Annotations
        # Supplies a chapter's wrapped plain-text lines at the *current*
        # layout, plus a signature identifying that layout.
        #
        # The line list mirrors what the renderer paints — same formatter,
        # same fallback chain (formatted wrap -> raw line wrapper -> raw
        # chapter lines), same column width and image-row sizing derived from
        # the live terminal size — so a line offset into this list is the
        # same coordinate the rendered geometry and the page map use.
        class ChapterStreamSource
          def initialize(document_provider:, chapter_formatter:, layout_service:,
                         reader_runtime_context:, config_reader:, line_wrapper: nil, logger: nil)
            unless chapter_formatter.is_a?(Shoko::Application::Ports::Outbound::ChapterFormatter)
              raise ArgumentError, 'chapter_formatter must implement Application::Ports::Outbound::ChapterFormatter'
            end
            if line_wrapper && !line_wrapper.is_a?(Shoko::Application::Ports::Outbound::LineWrapper)
              raise ArgumentError, 'line_wrapper must implement Application::Ports::Outbound::LineWrapper'
            end

            @document_provider = document_provider
            @chapter_formatter = chapter_formatter
            @layout_service = layout_service
            @reader_runtime_context = reader_runtime_context
            @config_reader = config_reader
            @line_wrapper = line_wrapper
            @logger = logger
          end

          Fetch = Data.define(:lines, :signature)

          # @return [Fetch, nil] the chapter's wrapped plain-text lines and a
          #   layout signature, or nil when no document/layout is available.
          def fetch(chapter_index)
            document = @document_provider&.call
            return nil unless document

            col_width, lines_per_page = current_layout
            return nil unless col_width&.positive?

            lines = wrapped_lines(document, chapter_index, col_width, lines_per_page)
            Fetch.new(
              lines: lines.map { |line| line_text(line) },
              signature: [document.object_id, chapter_index.to_i, col_width, lines_per_page]
            )
          end

          private

          def current_layout
            size = @reader_runtime_context.terminal_size
            width = positive_or(size.width, 80)
            height = positive_or(size.height, 24)
            effective_width = @layout_service.effective_content_width(width)
            col_width, content_height = @layout_service.calculate_metrics(effective_width, height, view_mode)
            [col_width, @layout_service.adjust_for_line_spacing(content_height, line_spacing)]
          end

          def wrapped_lines(document, chapter_index, col_width, lines_per_page)
            formatted = Array(
              @chapter_formatter.wrap_all(
                document, chapter_index, col_width,
                config: @config_reader, lines_per_page: lines_per_page
              )
            )
            return formatted unless formatted.empty?

            wrapper_lines(document, chapter_index, col_width)
          end

          def wrapper_lines(document, chapter_index, col_width)
            return [] unless @line_wrapper

            plain = Array(@chapter_formatter.plain_lines_for(document, chapter_index))
            return [] if plain.empty?

            Array(@line_wrapper.wrap_lines(plain, chapter_index, col_width, document: document))
          end

          def line_text(line)
            line.is_a?(String) ? line : line.text.to_s
          end

          def view_mode
            @config_reader&.view_mode || :single
          end

          def line_spacing
            @config_reader&.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
          end

          def positive_or(value, fallback)
            parsed = value.to_i
            parsed.positive? ? parsed : fallback
          end
        end
      end
    end
  end
end
