# frozen_string_literal: true

require 'rexml/document'
require 'rexml/security'

module Shoko
  module Adapters
    module Runtime
      # Applies process-global REXML security limits from runtime config.
      # This adapter keeps global parser mutations out of core domain code.
      class REXMLSecurityLimitsAdapter
        def initialize(runtime_config:)
          @runtime_config = runtime_config
        end

        def apply!
          limit = @runtime_config&.rexml_entity_expansion_limit
          text_limit = @runtime_config&.rexml_entity_expansion_text_limit

          if defined?(REXML::Security) && limit
            REXML::Security.entity_expansion_limit = limit
          end
          if defined?(REXML::Security) && text_limit
            REXML::Security.entity_expansion_text_limit = text_limit
          end
          if defined?(REXML::Document) && text_limit
            REXML::Document.entity_expansion_text_limit = text_limit
          end
        rescue NoMethodError, NameError
          nil
        end
      end
    end
  end
end
