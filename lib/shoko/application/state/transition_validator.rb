# frozen_string_literal: true

module Shoko
  module Application
    module State
      class StateStore
        # Validates state transition payloads before commit.
        #
        # The validator embeds cross-fragment invariants (e.g. current_chapter
        # bounds against total_chapters) that the state store as a single
        # coordinating service must enforce. These rules are application
        # policy and belong with the store.
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
              message = reader_transition_error(Array(path), value, new_state)
              return message if message
            end
            true
          end

          def validate_pagination_transitions(new_state:, updates:)
            updates.each do |path, value|
              message = pagination_transition_error(Array(path), value, new_state)
              return message if message
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

          def reader_transition_error(path_arr, value, new_state)
            return unless path_arr.first == :reader

            case path_arr
            when %i[reader current_chapter]
              chapter_bounds_error(value, new_state)
            when %i[reader left_page], %i[reader right_page], %i[reader single_page]
              negative_reader_value_error(path_arr.last, value)
            when %i[reader current_page_index]
              'current_page_index cannot be negative' if value.negative?
            end
          end

          def pagination_transition_error(path_arr, value, new_state)
            return unless path_arr.first == :reader

            case path_arr
            when %i[reader current_page_index]
              dynamic_page_bounds_error(value, new_state)
            when %i[reader total_pages], %i[reader dynamic_total_pages]
              negative_reader_value_error(path_arr.last, value)
            end
          end

          def chapter_bounds_error(value, new_state)
            total = new_state.dig(:reader, :total_chapters) || 0
            return unless total.positive? && value >= total

            "current_chapter (#{value}) cannot exceed total_chapters (#{total})"
          end

          def dynamic_page_bounds_error(value, new_state)
            total = new_state.dig(:reader, :dynamic_total_pages) || 0
            return unless total.positive? && value >= total

            "current_page_index (#{value}) cannot exceed dynamic_total_pages (#{total})"
          end

          def negative_reader_value_error(name, value)
            "#{name} cannot be negative" if value.negative?
          end
        end
      end
    end
  end
end
