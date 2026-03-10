# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          class IntentRuntimeBridge
            module DictionaryActions
              def open_dictionary
                :pass
              end

              def close_dictionary
                controller.close_dictionary
              end

              def dictionary_insert_text(text)
                controller.dictionary_insert_char(text.to_s)
              end

              def dictionary_backspace
                controller.dictionary_backspace
              end

              def dictionary_confirm
                controller.dictionary_confirm
              end

              def dictionary_move(delta)
                delta.negative? ? controller.dictionary_scroll_up : controller.dictionary_scroll_down
              end

              def dictionary_cycle_result
                controller.dictionary_cycle_result
              end

              def dictionary_cycle_pair
                controller.dictionary_cycle_pair
              end

              def dictionary_swap_languages
                controller.dictionary_swap_languages
              end

              def dictionary_toggle_fuzzy
                controller.dictionary_toggle_fuzzy
              end
            end
          end
        end
      end
    end
  end
end
