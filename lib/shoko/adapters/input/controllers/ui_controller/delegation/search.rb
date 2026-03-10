# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module UiControllerDelegation
          module Search
            def open_in_book_search(key = nil)
              @in_book_search_controller.open_in_book_search(key)
            end

            def close_in_book_search(key = nil)
              @in_book_search_controller.close_in_book_search(key)
            end

            def in_book_search_insert_char(char)
              @in_book_search_controller.in_book_search_insert_char(char)
            end

            def in_book_search_backspace(key = nil)
              @in_book_search_controller.in_book_search_backspace(key)
            end

            def in_book_search_confirm(key = nil)
              @in_book_search_controller.in_book_search_confirm(key)
            end

            def in_book_search_cancel(key = nil)
              @in_book_search_controller.in_book_search_cancel(key)
            end

            def in_book_search_up(key = nil)
              @in_book_search_controller.in_book_search_up(key)
            end

            def in_book_search_down(key = nil)
              @in_book_search_controller.in_book_search_down(key)
            end

            def in_book_search_visible?
              @in_book_search_controller.in_book_search_visible?
            end
          end
        end
      end
    end
  end
end
