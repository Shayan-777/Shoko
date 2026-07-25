# frozen_string_literal: true

module Shoko
  module Shared
    # Scoped thread-local binding: sets a key for the duration of a block and
    # always restores the previous value, including on a non-local exit.
    #
    # Four render/measure components each carried a private copy of this
    # save-restore dance against their own key. The key stays per-component —
    # they are independent bindings — but the mechanism is one behavior and
    # therefore has one home (constitution R1: two or more call sites earn a
    # single implementation).
    module ThreadLocalScope
      module_function

      # @param key [Symbol] thread-local key to bind
      # @param value [Object, nil] value to bind; nil leaves the binding untouched
      # @return [Object] the block's value
      def with(key:, value:)
        previous = Thread.current[key]
        Thread.current[key] = value if value
        yield
      ensure
        Thread.current[key] = previous
      end
    end
  end
end
