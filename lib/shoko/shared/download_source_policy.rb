# frozen_string_literal: true

module Shoko
  module Shared
    # Shared normalization and validation rules for persisted download source identity.
    module DownloadSourcePolicy
      DEFAULT_ID = :gutendex
      CANONICAL_IDS = %i[gutendex libgen].freeze
      LABELS = {
        gutendex: 'Gutendex',
        libgen: 'Libgen',
      }.freeze

      module_function

      def default_id
        DEFAULT_ID
      end

      def canonical_ids
        CANONICAL_IDS
      end

      def normalize(value)
        key = normalize_key(value)
        return nil unless key

        CANONICAL_IDS.include?(key) ? key : nil
      end

      def valid?(value)
        !normalize(value).nil?
      end

      def label_for(value)
        normalized = normalize(value) || DEFAULT_ID
        LABELS.fetch(normalized)
      end

      def normalize_key(value)
        return nil if value.nil?

        key = value.is_a?(Symbol) ? value : value.to_s.strip.downcase.to_sym
        return nil if key == :''

        key
      end
      private_class_method :normalize_key
    end
  end
end
