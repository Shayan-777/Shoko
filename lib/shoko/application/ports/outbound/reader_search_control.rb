# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Capability port for reader in-book search interaction. Query, result,
        # and selection state are observable in the reader view-state store and
        # are written by the search use case; the popup component re-renders from
        # that state. The methods below are the operations that still need adapter
        # coordination: surface lifecycle (popup create/teardown + modal mode),
        # running the document-bound search service, and navigating to a result
        # (which needs the rendered/paginated document).
        module ReaderSearchControl
          def open_search_session
            raise NotImplementedError, "#{self.class} must implement #open_search_session"
          end

          def close_search_session
            raise NotImplementedError, "#{self.class} must implement #close_search_session"
          end

          def submit_search_session
            raise NotImplementedError, "#{self.class} must implement #submit_search_session"
          end

          def open_search_result(result)
            raise NotImplementedError, "#{self.class} must implement #open_search_result"
          end
        end
      end
    end
  end
end
