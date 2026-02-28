# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Inbound
        # Typed context contract for reader bookmark command execution.
        module ReaderBookmarkCommandContext
          def bookmark_service
            raise NotImplementedError, "#{self.class} must implement #bookmark_service"
          end
        end
      end
    end
  end
end
