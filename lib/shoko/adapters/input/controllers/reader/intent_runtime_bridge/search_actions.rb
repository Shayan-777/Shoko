# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          class IntentRuntimeBridge
            # Maps reader search intents onto the residual in-book search
            # controller operations. Query and selection state are owned by the
            # state store and written application-side; only surface lifecycle,
            # search execution, and result navigation remain here.
            module SearchActions
              def open_search_session
                controller.open_in_book_search
              end

              def close_search_session
                controller.close_in_book_search
              end

              def submit_search_session
                controller.submit_in_book_search
              end

              def open_search_result(result)
                controller.open_search_result(result)
              end
            end
          end
        end
      end
    end
  end
end
