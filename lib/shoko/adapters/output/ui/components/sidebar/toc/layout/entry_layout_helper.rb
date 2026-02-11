# frozen_string_literal: true

module Shoko
  module Adapters::Output::Ui::Components
    module Sidebar
      # Calculates wrapped lines and widths for entries.
      class EntryLayoutHelper
        def self.wrap_lines(entry, max_width, wrap_cache, text_metrics)
          width = available_width(entry, max_width)
          return [''] if width <= 0

          cache = wrap_cache
          key = [entry.object_id, width]
          if cache
            cache[key] ||= text_metrics.wrap_plain_text(formatted_title(entry), width)
          else
            text_metrics.wrap_plain_text(formatted_title(entry), width)
          end
        end

        def self.line_count(entry, max_width, wrap_cache, text_metrics)
          wrap_lines(entry, max_width, wrap_cache, text_metrics).length
        end

        def self.available_width(entry, max_width)
          width = max_width - width_without_title(entry)
          [width, 0].max
        end

        def self.width_without_title(entry)
          level = entry.level.to_i
          level = 0 if level.negative?
          (level * 2) + 2
        end

        def self.formatted_title(entry)
          EntryTitleFormatter.format(entry)
        end

        private_class_method :available_width, :width_without_title, :formatted_title
      end
    end
  end
end
