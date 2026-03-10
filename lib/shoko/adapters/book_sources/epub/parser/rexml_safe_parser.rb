# frozen_string_literal: true

require 'rexml/document'
require 'rexml/security'

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Centralized REXML parser entrypoint.
        # Security limits are configured externally in composition/runtime adapters.
        module REXMLSafeParser
          module_function

          def parse(xml)
            REXML::Document.new(xml)
          end
        end
      end
    end
  end
end
