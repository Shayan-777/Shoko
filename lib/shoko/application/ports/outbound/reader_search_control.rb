# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Capability port for reader in-book search interaction.
        module ReaderSearchControl
          def open_search_session
            raise NotImplementedError, "#{self.class} must implement #open_search_session"
          end

          def close_search_session
            raise NotImplementedError, "#{self.class} must implement #close_search_session"
          end

          def append_search_text(text)
            raise NotImplementedError, "#{self.class} must implement #append_search_text"
          end

          def delete_search_character
            raise NotImplementedError, "#{self.class} must implement #delete_search_character"
          end

          def submit_search_session
            raise NotImplementedError, "#{self.class} must implement #submit_search_session"
          end

          def move_search_selection(delta:)
            raise NotImplementedError, "#{self.class} must implement #move_search_selection"
          end
        end
      end
    end
  end
end
