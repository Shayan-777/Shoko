# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port for in-book search popup lifecycle and interactions.
      module InBookSearchUiSession
        def open(query: '', results: [], total_matches: 0)
          raise NotImplementedError, "#{self.class} must implement #open"
        end

        def close
          raise NotImplementedError, "#{self.class} must implement #close"
        end

        def visible?
          raise NotImplementedError, "#{self.class} must implement #visible?"
        end

        def insert_char(char)
          raise NotImplementedError, "#{self.class} must implement #insert_char"
        end

        def backspace
          raise NotImplementedError, "#{self.class} must implement #backspace"
        end

        def confirm
          raise NotImplementedError, "#{self.class} must implement #confirm"
        end

        def cancel
          raise NotImplementedError, "#{self.class} must implement #cancel"
        end

        def scroll_up
          raise NotImplementedError, "#{self.class} must implement #scroll_up"
        end

        def scroll_down
          raise NotImplementedError, "#{self.class} must implement #scroll_down"
        end

        def update(query:, results:, total_matches:, results_query:)
          raise NotImplementedError, "#{self.class} must implement #update"
        end
      end
    end
  end
end
