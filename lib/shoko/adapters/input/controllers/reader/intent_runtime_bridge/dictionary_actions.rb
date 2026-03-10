# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          class IntentRuntimeBridge
            module DictionaryActions
              def open_dictionary_lookup
                :pass
              end

              def close_dictionary_lookup
                controller.close_dictionary
              end

              def append_dictionary_text(text)
                controller.dictionary_insert_char(text.to_s)
              end

              def delete_dictionary_character
                controller.dictionary_backspace
              end

              def submit_dictionary_lookup
                controller.dictionary_confirm
              end

              def move_dictionary_selection(delta:)
                delta.negative? ? controller.dictionary_scroll_up : controller.dictionary_scroll_down
              end

              def cycle_dictionary_result
                controller.dictionary_cycle_result
              end

              def cycle_dictionary_pair
                controller.dictionary_cycle_pair
              end

              def swap_dictionary_languages
                controller.dictionary_swap_languages
              end

              def toggle_dictionary_fuzzy_matching
                controller.dictionary_toggle_fuzzy
              end
            end
          end
        end
      end
    end
  end
end
