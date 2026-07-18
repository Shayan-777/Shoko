# frozen_string_literal: true

module Shoko
  module Zip
    # Resolves limit values from explicit arguments or defaults.
    class LimitResolver
      def self.resolve(value, default:)
        new(value, default).resolve
      end

      def initialize(value, default)
        @value = value
        @default = default
      end

      def resolve
        parsed = parse_integer(@value)
        valid_positive_or_default(parsed)
      end

      private

      def parse_integer(candidate)
        return nil if candidate.nil?

        Integer(candidate)
      end

      def valid_positive_or_default(parsed)
        parsed&.positive? ? parsed : @default
      end
    end
  end
end
