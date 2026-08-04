# frozen_string_literal: true

require_relative '../../application/ports/outbound/async_executor'

module Shoko
  module Adapters
    module Runtime
      # Executes submitted work immediately on the caller thread.
      class InlineExecutorAdapter
        include Shoko::Application::Ports::Outbound::AsyncExecutor

        def submit(&)
          raise ArgumentError, 'block required' unless block_given?

          yield
        end

        def synchronous? = true

        def shutdown(timeout: nil) = nil # rubocop:disable Lint/UnusedMethodArgument
      end
    end
  end
end
