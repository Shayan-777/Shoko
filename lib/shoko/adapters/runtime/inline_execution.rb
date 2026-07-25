# frozen_string_literal: true

module Shoko
  module Adapters
    module Runtime
      # Recognises the executor that runs work on the calling thread.
      #
      # Callers branch on this to decide whether "submit" means "already done"
      # — the reader lifecycle skips its async bookkeeping, and the composition
      # root skips wiring a drain. The adapter is optional at runtime, so the
      # check tolerates it not being loaded.
      module InlineExecution
        module_function

        def inline?(executor)
          return false unless executor
          return false unless defined?(Shoko::Adapters::Runtime::InlineExecutorAdapter)

          executor.is_a?(Shoko::Adapters::Runtime::InlineExecutorAdapter)
        end
      end
    end
  end
end
