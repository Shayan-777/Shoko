# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port interface for loading a document for a source path.
        module DocumentLoader
          # @param path [String]
          # @param progress_reporter [Object, nil] Progress reporter with #update_status
          # @param background_worker [Application::Ports::Outbound::AsyncExecutor, nil]
          # @return [Object] Loaded document
          def load(path:, progress_reporter: nil, background_worker: nil)
            raise NotImplementedError, "#{self.class} must implement #load"
          end
        end
      end
    end
  end
end
