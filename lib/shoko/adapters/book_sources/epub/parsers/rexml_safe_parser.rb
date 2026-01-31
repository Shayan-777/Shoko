# frozen_string_literal: true

require 'rexml/document'
require 'rexml/security'

module Shoko
  module Adapters::BookSources::Epub::Parsers
    # Centralized REXML parser with hardened entity expansion limits.
    module REXMLSafeParser
      module_function

      DEFAULT_ENTITY_EXPANSION_LIMIT = 10_000
      DEFAULT_ENTITY_EXPANSION_TEXT_LIMIT = 2_000_000

      def parse(xml)
        apply_security_limits
        REXML::Document.new(xml)
      end

      def apply_security_limits
        limit = integer_env('SHOKO_REXML_ENTITY_LIMIT', DEFAULT_ENTITY_EXPANSION_LIMIT)
        text_limit = integer_env('SHOKO_REXML_TEXT_LIMIT', DEFAULT_ENTITY_EXPANSION_TEXT_LIMIT)

        if defined?(REXML::Security) && REXML::Security.respond_to?(:entity_expansion_limit=)
          REXML::Security.entity_expansion_limit = limit
        end
        if defined?(REXML::Security) && REXML::Security.respond_to?(:entity_expansion_text_limit=)
          REXML::Security.entity_expansion_text_limit = text_limit
        end
        if defined?(REXML::Document) && REXML::Document.respond_to?(:entity_expansion_text_limit=)
          REXML::Document.entity_expansion_text_limit = text_limit
        end
      rescue StandardError
        nil
      end
      private_class_method :apply_security_limits

      def integer_env(key, fallback)
        value = ENV.fetch(key, '').to_s.strip
        return fallback if value.empty?

        parsed = value.to_i
        parsed.positive? ? parsed : fallback
      rescue StandardError
        fallback
      end
      private_class_method :integer_env
    end
  end
end
