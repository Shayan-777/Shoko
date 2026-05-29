# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module UiControllerDelegation
          # Delegates in-book search commands to the search controller.
          module Search
            def open_in_book_search(key = nil)
              @in_book_search_controller.open_in_book_search(key)
            end

            def close_in_book_search(key = nil)
              @in_book_search_controller.close_in_book_search(key)
            end

            def submit_in_book_search(key = nil)
              @in_book_search_controller.submit_in_book_search(key)
            end

            def open_search_result(result)
              @in_book_search_controller.open_search_result(result)
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
