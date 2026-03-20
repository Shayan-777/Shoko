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

          apply_entity_expansion_limit(limit)
          apply_entity_expansion_text_limit(text_limit)
        end

        def apply_entity_expansion_limit(limit)
          return unless limit

          REXML::Security.entity_expansion_limit = limit
        end

        def apply_entity_expansion_text_limit(text_limit)
          return unless text_limit

          REXML::Security.entity_expansion_text_limit = text_limit
          REXML::Document.entity_expansion_text_limit = text_limit
        end
      end
    end
  end
end
