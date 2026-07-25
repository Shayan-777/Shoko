# frozen_string_literal: true

require_relative 'policy_key'

module Shoko
  module Shared
    # Shared normalization and validation rules for persisted theme identity.
    module ThemePolicy
      DEFAULT_ID = :default
      CANONICAL_IDS = %i[default gray sepia grass cherry sky solarized gruvbox nord].freeze
      ALIASES = { standard: :default, dark: :default, light: :gray }.freeze

      module_function

      def default_id
        DEFAULT_ID
      end

      def canonical_ids
        CANONICAL_IDS
      end

      def aliases
        ALIASES
      end

      def normalize(value)
        key = PolicyKey.normalize(value)
        return nil unless key

        canonical = ALIASES.fetch(key, key)
        return canonical if CANONICAL_IDS.include?(canonical)

        nil
      end

      def valid?(value)
        !normalize(value).nil?
      end
    end
  end
end
