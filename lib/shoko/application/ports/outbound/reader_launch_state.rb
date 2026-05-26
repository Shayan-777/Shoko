# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Runtime launch-state contract for reader composition/workflow handoff.
        module ReaderLaunchState
          def preloaded_document
            raise NotImplementedError, "#{self.class} must implement #preloaded_document"
          end

          def preloaded_document=(_document)
            raise NotImplementedError, "#{self.class} must implement #preloaded_document="
          end

          def clear_preloaded_document
            raise NotImplementedError, "#{self.class} must implement #clear_preloaded_document"
          end

          def background_worker
            raise NotImplementedError, "#{self.class} must implement #background_worker"
          end

          def background_worker=(_worker)
            raise NotImplementedError, "#{self.class} must implement #background_worker="
          end

          def clear_background_worker
            raise NotImplementedError, "#{self.class} must implement #clear_background_worker"
          end
        end
      end
    end
  end
end
