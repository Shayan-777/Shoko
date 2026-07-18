# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Internal
        # Port interface for loading a document for a source path.
        module DocumentLoader
          # @param path [String]
          # @param progress_reporter [Object, nil] Progress reporter with #update_status
          # @return [Object] Loaded document
          def load(path:, progress_reporter: nil)
            raise NotImplementedError, "#{self.class} must implement #load"
          end
        end
      end
    end
  end
end
