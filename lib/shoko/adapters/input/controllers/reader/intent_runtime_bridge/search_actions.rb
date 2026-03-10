# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          class IntentRuntimeBridge
            module SearchActions
              def open_in_book_search
                controller.open_in_book_search
              end

              def close_in_book_search
                controller.close_in_book_search
              end

              def search_insert_text(text)
                controller.in_book_search_insert_char(text.to_s)
              end

              def search_backspace
                controller.in_book_search_backspace
              end

              def search_confirm
                controller.in_book_search_confirm
              end

              def search_move(delta)
                delta.negative? ? controller.in_book_search_up : controller.in_book_search_down
              end
            end
          end
        end
      end
    end
  end
end
