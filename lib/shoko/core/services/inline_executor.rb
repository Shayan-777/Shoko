# frozen_string_literal: true

require_relative '../ports/async_executor'

module Shoko
  module Core
    module Services
      # Executes submitted work immediately on the caller thread.
      class InlineExecutor
        include Core::Ports::AsyncExecutor

        def submit(&)
          raise ArgumentError, 'block required' unless block_given?

          yield
        end

        def shutdown(_timeout = nil)
          nil
        end
      end
    end
  end
end
