# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port interface for loading and persisting reader UI/view state.
        module ReaderViewStateStore
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
