# frozen_string_literal: true

require_relative 'error'
require_relative 'limit_resolver'
require_relative 'limits'
require_relative 'validation_context'

module Shoko
  module Zip
    # Manages size limits and validation for ZIP entries
    class SizeLimits
      attr_reader :max_entry_compressed, :max_entry_uncompressed, :max_total_uncompressed

      def initialize(max_entry_uncompressed:, max_entry_compressed:, max_total_uncompressed:)
        @max_entry_uncompressed = LimitResolver.resolve(max_entry_uncompressed, default: Limits::MAX_ENTRY_UNCOMPRESSED)
        @max_entry_compressed = LimitResolver.resolve(max_entry_compressed, default: Limits::MAX_ENTRY_COMPRESSED)
        @max_total_uncompressed = LimitResolver.resolve(max_total_uncompressed, default: Limits::MAX_TOTAL_UNCOMPRESSED)
        @total_uncompressed_bytes = 0
      end

      def enforce_entry_limits(entry, requested_name:)
        context = ValidationContext.new(entry, requested_name)
        validate_compressed_size(context)
        validate_uncompressed_size(context)
        validate_total_budget(context)
      end

      def enforce_uncompressed_budget(entry, actual_bytes)
        entry_name = entry.name
        validate_entry_size(entry_name, actual_bytes)
        validate_archive_budget(entry_name, actual_bytes)
      end

      def register_uncompressed_bytes(entry, byte_count)
        enforce_uncompressed_budget(entry, byte_count)
        increment_total(byte_count)
      end

      def current_total
        @total_uncompressed_bytes
      end

      private

      def increment_total(byte_count)
        @total_uncompressed_bytes += byte_count
      end

      def validate_compressed_size(context)
        return unless context.compressed_size > max_entry_compressed

        raise Error, "entry too large (compressed): #{context.requested_name}"
      end

      def validate_uncompressed_size(context)
        return unless context.exceeds_uncompressed_limit?(max_entry_uncompressed)

        raise Error, "entry too large (uncompressed): #{context.requested_name}"
      end

      def validate_total_budget(context)
        return unless context.uncompressed_size_positive?

        uncompressed_size = context.uncompressed_size
        new_total = current_total + uncompressed_size
        return unless new_total > max_total_uncompressed

        raise Error, "archive exceeds total uncompressed limit: #{context.requested_name}"
      end

      def validate_entry_size(entry_name, actual_bytes)
        return unless actual_bytes > max_entry_uncompressed

        raise Error, "entry too large after decompression: #{entry_name}"
      end

      def validate_archive_budget(entry_name, actual_bytes)
        new_total = current_total + actual_bytes
        return unless new_total > max_total_uncompressed

        raise Error, "archive exceeds total uncompressed limit: #{entry_name}"
      end
    end
  end
end
