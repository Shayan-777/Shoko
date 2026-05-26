# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port for importing a discovered document into cache/storage.
        module FolderImporter
          # @param progress_reporter [Object, nil] Progress reporter with #update_status
          # @return [Symbol] :imported or :skipped
          def import(_path, progress_reporter: nil)
            raise NotImplementedError, "#{self.class} must implement #import"
          end
        end
      end
    end
  end
end
