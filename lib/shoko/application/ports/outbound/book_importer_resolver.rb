# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Boundary for importing a source file into core book data.
        module BookImporterResolver
          def import(path, progress_reporter: nil, runtime_config: nil, logger: nil)
            raise NotImplementedError, "#{self.class} must implement #import"
          end
        end
      end
    end
  end
end
