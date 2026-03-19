# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port interface for loading and persisting menu transient workflow state.
        module MenuTransientStore
          def load
            raise NotImplementedError, "#{self.class} must implement #load"
          end

          def save(snapshot)
            raise NotImplementedError, "#{self.class} must implement #save"
          end

          def update
            raise NotImplementedError, "#{self.class} must implement #update"
          end
        end
      end
    end
  end
end
