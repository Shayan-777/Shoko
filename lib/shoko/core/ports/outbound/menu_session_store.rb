# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port interface for loading and persisting the menu session snapshot.
        module MenuSessionStore
          def load
            raise NotImplementedError, "#{self.class} must implement #load"
          end

          def save(snapshot)
            raise NotImplementedError, "#{self.class} must implement #save"
          end
        end
      end
    end
  end
end
