# frozen_string_literal: true

module Shoko
  module Shared
    # Resolves a dependency the first time it is used and then forwards calls.
    class LazyProxy
      def initialize(&resolver)
        raise ArgumentError, 'resolver block is required' unless resolver

        @resolver = resolver
        @mutex = Mutex.new
      end

      def __target__
        return @target if instance_variable_defined?(:@target)

        @mutex.synchronize do
          return @target if instance_variable_defined?(:@target)

          @target = @resolver.call
        end

        @target
      end

      def respond_to_missing?(name, include_private = false)
        __target__.respond_to?(name, include_private)
      end

      def method_missing(name, ...)
        __target__.public_send(name, ...)
      end

      def is_a?(klass)
        __target__.is_a?(klass)
      end
      alias kind_of? is_a?

      def class
        __target__.class
      end

      def nil?
        return @target.nil? if instance_variable_defined?(:@target)

        false
      end

      def inspect
        if instance_variable_defined?(:@target)
          "#<#{self.class} target=#{@target.inspect}>"
        else
          "#<#{self.class} unresolved>"
        end
      end
    end
  end
end
