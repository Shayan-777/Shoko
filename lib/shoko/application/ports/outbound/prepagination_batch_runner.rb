# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port for executing the library pre-pagination batch in an isolated
        # worker process. Process isolation is the point: pagination is
        # CPU-bound, and inside this process even a low-priority thread holds
        # the GIL and starves the render loop, so the batch must run where the
        # OS scheduler — not the Ruby interpreter — arbitrates the CPU.
        module PrepaginationBatchRunner
          # Run one batch for the given terminal dimensions, blocking until it
          # finishes. Implementations stream normalized progress events
          # (hashes with a :event key: 'start', 'report', 'finish') to
          # +on_event+ as they arrive.
          #
          # @return [Symbol] :completed, :failed, or :cancelled
          def run_batch(width:, height:, on_event:)
            raise NotImplementedError, "#{self.class} must implement #run_batch"
          end

          # Interrupt a running batch (idempotent; safe when none is running).
          def cancel_batch
            raise NotImplementedError, "#{self.class} must implement #cancel_batch"
          end
        end
      end
    end
  end
end
