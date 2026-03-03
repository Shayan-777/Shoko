# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Selection boundary for resolving the active/filtered menu books.
        module MenuBookSelection
          # @return [Core::Models::MenuBook, nil]
          def selected_book
            raise NotImplementedError, "#{self.class} must implement #selected_book"
          end

          # @return [Array<Core::Models::MenuBook>]
          def filtered_books
            raise NotImplementedError, "#{self.class} must implement #filtered_books"
          end
        end
      end
    end
  end
end
