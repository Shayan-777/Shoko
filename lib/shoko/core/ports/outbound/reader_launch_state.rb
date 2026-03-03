# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Runtime launch-state contract for reader bootstrap/workflow handoff.
        module ReaderLaunchState
          def preloaded_document
            raise NotImplementedError, "#{self.class} must implement #preloaded_document"
          end

          def set_preloaded_document(_document)
            raise NotImplementedError, "#{self.class} must implement #set_preloaded_document"
          end

          def clear_preloaded_document
            raise NotImplementedError, "#{self.class} must implement #clear_preloaded_document"
          end

          def background_worker
            raise NotImplementedError, "#{self.class} must implement #background_worker"
          end

          def set_background_worker(_worker)
            raise NotImplementedError, "#{self.class} must implement #set_background_worker"
          end

          def clear_background_worker
            raise NotImplementedError, "#{self.class} must implement #clear_background_worker"
          end
        end
      end
    end
  end
end
