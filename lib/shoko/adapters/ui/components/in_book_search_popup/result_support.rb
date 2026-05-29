# frozen_string_literal: true

require_relative '../base_component'

module Shoko
  module Adapters
    module Ui
      module Components
        class InBookSearchPopupComponent < BaseComponent
          # Result normalization and selection helpers for the search popup.
          module ResultSupport
            private

            def normalize_results(results)
              Array(results).filter_map do |entry|
                next unless entry

                if entry.is_a?(Hash)
                  normalize_result_hash(entry)
                elsif entry.is_a?(Struct) || entry.is_a?(Data)
                  normalize_result_hash(entry.to_h)
                end
              end
            end

            def normalize_result_hash(entry)
              {
                chapter_index: normalize_result_number(entry, :chapter_index),
                chapter_title: normalize_result_text(entry, :chapter_title),
                line_index: normalize_result_number(entry, :line_index),
                before: normalize_result_text(entry, :before),
                match: normalize_result_text(entry, :match),
                after: normalize_result_text(entry, :after),
                line_space: normalize_result_text(entry, :line_space),
                page_index: normalize_optional_result_number(entry, :page_index),
              }
            end

            def normalize_result_number(entry, key)
              result_value(entry, key).to_i
            end

            def normalize_optional_result_number(entry, key)
              value = result_value(entry, key)
              return nil if value.nil? || value.to_s.strip.empty?

              Shoko::Shared::TypeCoercion.optional_integer(value)
            end

            def normalize_result_text(entry, key)
              result_value(entry, key).to_s
            end

            def result_value(entry, key)
              return entry[key] if entry.key?(key)

              entry[key.to_s]
            end

            def query_needs_search?
              @query.to_s.strip != @results_query.to_s.strip
            end

            def ensure_selection_visible!
              visible = [@last_visible_cards, 1].max
              if @selected_index < @scroll_offset
                @scroll_offset = @selected_index
              elsif @selected_index >= (@scroll_offset + visible)
                @scroll_offset = @selected_index - visible + 1
              end
              clamp_scroll!
            end

            def clamp_selection!
              @selected_index = if @results.empty?
                                  0
                                else
                                  @selected_index.clamp(0, @results.length - 1)
                                end
            end

            def clamp_scroll!
              max = [@results.length - [@last_visible_cards, 1].max, 0].max
              @scroll_offset = @scroll_offset.clamp(0, max)
            end
          end
        end
      end
    end
  end
end
