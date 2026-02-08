# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for process-level runtime configuration.
      # Implementations adapt environment variables or other runtime sources.
      module RuntimeConfig
        # @return [Boolean]
        def skip_progress_overlay?
          raise NotImplementedError, "#{self.class} must implement #skip_progress_overlay?"
        end

        # @return [String, nil] e.g. "sqlite"
        def dictionary_backend_override
          raise NotImplementedError, "#{self.class} must implement #dictionary_backend_override"
        end

        # @return [Integer]
        def rexml_entity_expansion_limit
          raise NotImplementedError, "#{self.class} must implement #rexml_entity_expansion_limit"
        end

        # @return [Integer]
        def rexml_entity_expansion_text_limit
          raise NotImplementedError, "#{self.class} must implement #rexml_entity_expansion_text_limit"
        end
      end
    end
  end
end
