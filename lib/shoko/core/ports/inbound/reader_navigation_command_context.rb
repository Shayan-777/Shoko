# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Inbound
        # Typed context contract for reader navigation command execution.
        module ReaderNavigationCommandContext
          def navigation_service
            raise NotImplementedError, "#{self.class} must implement #navigation_service"
          end

          def reader_state_reader
            raise NotImplementedError, "#{self.class} must implement #reader_state_reader"
          end
        end
      end
    end
  end
end
