# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Boundary for importing a source file into core book data.
        #
        # Implementers construct format importers through the uniform
        # contract `new(progress_reporter:, runtime_config:)` — every
        # registered importer accepts both keywords.
        module BookImporterResolver
          def import(path, progress_reporter: nil, runtime_config: nil)
            raise NotImplementedError, "#{self.class} must implement #import"
          end
        end
      end
    end
  end
end
