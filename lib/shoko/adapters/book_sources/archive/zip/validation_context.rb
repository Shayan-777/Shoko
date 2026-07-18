# frozen_string_literal: true

module Shoko
  module Zip
    # Helpers for indexing entries via the Central Directory.
    # Context for entry validation operations
    class ValidationContext
      attr_reader :entry, :requested_name

      def initialize(entry, requested_name)
        @entry = entry
        @requested_name = requested_name
      end

      def compressed_size
        entry.compressed_size.to_i
      end

      def uncompressed_size
        @uncompressed_size ||= entry.uncompressed_size.to_i
      end

      def uncompressed_size_positive?
        uncompressed_size.positive?
      end

      def entry_name
        entry.name
      end

      def exceeds_uncompressed_limit?(max_limit)
        uncompressed_size_positive? && uncompressed_size > max_limit
      end
    end
  end
end
