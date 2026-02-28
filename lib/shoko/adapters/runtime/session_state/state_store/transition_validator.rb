# frozen_string_literal: true

module Shoko
  module Adapters
    module Runtime
      module SessionState
        class StateStore
          # Validates state transition payloads before commit.
          class TransitionValidator
            def validate(old_state:, new_state:, updates:)
              _old_state = old_state
              result = validate_reader_transitions(new_state: new_state, updates: updates)
              return result unless result == true

              result = validate_pagination_transitions(new_state: new_state, updates: updates)
              return result unless result == true

              validate_sidebar_transitions(updates: updates)
            end

            private

            def validate_reader_transitions(new_state:, updates:)
              updates.each do |path, value|
                path_arr = Array(path)
                next unless path_arr.first == :reader

                case path_arr
                when %i[reader current_chapter]
                  total = new_state.dig(:reader, :total_chapters) || 0
                  if total.positive? && value >= total
                    return "current_chapter (#{value}) cannot exceed total_chapters (#{total})"
                  end
                when %i[reader left_page], %i[reader right_page], %i[reader single_page]
                  return "#{path_arr.last} cannot be negative" if value.negative?
                when %i[reader current_page_index]
                  return 'current_page_index cannot be negative' if value.negative?
                end
              end
              true
            end

            def validate_pagination_transitions(new_state:, updates:)
              updates.each do |path, value|
                path_arr = Array(path)
                next unless path_arr.first == :reader

                case path_arr
                when %i[reader current_page_index]
                  total = new_state.dig(:reader, :dynamic_total_pages) || 0
                  if total.positive? && value >= total
                    return "current_page_index (#{value}) cannot exceed dynamic_total_pages (#{total})"
                  end
                when %i[reader total_pages], %i[reader dynamic_total_pages]
                  return "#{path_arr.last} cannot be negative" if value.negative?
                end
              end
              true
            end

            def validate_sidebar_transitions(updates:)
              updates.each do |path, value|
                path_arr = Array(path)
                next unless path_arr.first == :reader

                case path_arr
                when %i[reader sidebar_toc_selected],
                     %i[reader sidebar_annotations_selected],
                     %i[reader sidebar_bookmarks_selected]
                  return "#{path_arr.last} cannot be negative" if value.negative?
                when %i[reader sidebar_active_tab]
                  valid_tabs = %i[toc bookmarks annotations]
                  return "Invalid sidebar tab: #{value}" unless valid_tabs.include?(value)
                end
              end
              true
            end
          end
        end
      end
    end
  end
end
