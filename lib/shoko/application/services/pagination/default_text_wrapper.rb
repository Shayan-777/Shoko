# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Pagination
        # Default text wrapping implementation for pagination workflows.
        class DefaultTextWrapper
          # @param text_metrics [Application::Ports::Outbound::TextMetrics] Required text metrics implementation
          def initialize(text_metrics:)
            raise ArgumentError, 'text_metrics is required' unless text_metrics

            @text_metrics = text_metrics
          end

          def wrap_chapter_lines(lines, column_width)
            return [] if lines.empty? || column_width <= 0

            lines.each_with_object([]) do |line, wrapped|
              next if line.nil?

              append_wrapped_line(wrapped, line, column_width)
            end
          end

          private

          def append_wrapped_line(wrapped, line, column_width)
            return wrapped << '' if line.strip.empty?

            wrapped.concat(@text_metrics.wrap_plain_text(line, column_width))
          end
        end
      end
    end
  end
end
