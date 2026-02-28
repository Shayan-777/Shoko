# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port for importing a discovered document into cache/storage.
        module FolderImporter
          # @return [Symbol] :imported or :skipped
          def import(_path)
            raise NotImplementedError, "#{self.class} must implement #import"
          end
        end
      end
    end
  end
end
