# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port for recursively scanning a folder and returning import candidates.
        module FolderScanner
          Entry = Data.define(:path, :format_group, :format_extension)

          def scan(_directory_path, recursive:, skip_hidden:)
            raise NotImplementedError, "#{self.class} must implement #scan"
          end
        end
      end
    end
  end
end
