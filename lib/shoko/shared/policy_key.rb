# frozen_string_literal: true

module Shoko
  module Shared
    # Canonicalizes a persisted enum-style identifier into a comparable Symbol.
    #
    # Config values reach the policies as either Symbols (in-memory) or Strings
    # (round-tripped through JSON), with arbitrary case and padding. The
    # download-source and theme policies apply the identical rule, so it lives
    # here once — a drift between them would mean the same stored value
    # validating under one policy and not the other.
    module PolicyKey
      module_function

      # @return [Symbol, nil] nil for nil input or an effectively empty value
      def normalize(value)
        return nil if value.nil?

        key = value.is_a?(Symbol) ? value : value.to_s.strip.downcase.to_sym
        return nil if key == :''

        key
      end
    end
  end
end
