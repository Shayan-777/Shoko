# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port interface for checking dictionary backend availability.
        # Adapters implementing this interface should detect whether the
        # required dictionary infrastructure (e.g. SQLite) is available.
        module DictionaryAvailability
          # Check if the SQLite3 library is available
          #
          # @return [Boolean]
          def sqlite3_available?
            raise NotImplementedError, "#{self.class} must implement #sqlite3_available?"
          end
        end
      end
    end
  end
end
