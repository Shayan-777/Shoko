# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      # Port for in-book search popup lifecycle and interactions.
      module InBookSearchUiSession
        # Mutation command: returns Application::UI::SessionOutcome.
        def open(query: '', results: [], total_matches: 0)
          raise NotImplementedError, "#{self.class} must implement #open"
        end

        # Mutation command: returns Application::UI::SessionOutcome.
        def close
          raise NotImplementedError, "#{self.class} must implement #close"
        end

        # Query/predicate: returns boolean.
        def visible?
          raise NotImplementedError, "#{self.class} must implement #visible?"
        end

        # Mutation command: returns Application::UI::SessionOutcome.
        def insert_char(char)
          raise NotImplementedError, "#{self.class} must implement #insert_char"
        end

        # Mutation command: returns Application::UI::SessionOutcome.
        def backspace
          raise NotImplementedError, "#{self.class} must implement #backspace"
        end

        # Mutation command: returns Application::UI::SessionOutcome.
        def confirm
          raise NotImplementedError, "#{self.class} must implement #confirm"
        end

        # Mutation command: returns Application::UI::SessionOutcome.
        def cancel
          raise NotImplementedError, "#{self.class} must implement #cancel"
        end

        # Mutation command: returns Application::UI::SessionOutcome.
        def scroll_up
          raise NotImplementedError, "#{self.class} must implement #scroll_up"
        end

        # Mutation command: returns Application::UI::SessionOutcome.
        def scroll_down
          raise NotImplementedError, "#{self.class} must implement #scroll_down"
        end

        # Mutation command: returns Application::UI::SessionOutcome.
        def update(query:, results:, total_matches:, results_query:)
          raise NotImplementedError, "#{self.class} must implement #update"
        end
      end
    end
  end
end
