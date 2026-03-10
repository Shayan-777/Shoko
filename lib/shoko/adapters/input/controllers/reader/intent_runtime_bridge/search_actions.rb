# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          class IntentRuntimeBridge
            module SearchActions
              def open_search_session
                controller.open_in_book_search
              end

              def close_search_session
                controller.close_in_book_search
              end

              def append_search_text(text)
                controller.in_book_search_insert_char(text.to_s)
              end

              def delete_search_character
                controller.in_book_search_backspace
              end

              def submit_search_session
                controller.in_book_search_confirm
              end

              def move_search_selection(delta:)
                delta.negative? ? controller.in_book_search_up : controller.in_book_search_down
              end
            end
          end
        end
      end
    end
  end
end
