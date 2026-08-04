# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Thread-safe mailbox for worker-to-reader render signals and relays.
          # It coalesces redraw requests while keeping all rendering on the UI
          # thread. Relay registration may happen during runtime assembly while
          # worker threads are already publishing results.
          class RenderMailbox
            def initialize(wake_input:)
              @wake_input = wake_input
              @mutex = Mutex.new
              @render_pending = false
              @relays = []
            end

            def request
              @mutex.synchronize { @render_pending = true }
              @wake_input.call
              nil
            end

            def consume?
              @mutex.synchronize do
                pending = @render_pending
                @render_pending = false
                pending
              end
            end

            def register(relay)
              raise ArgumentError, 'relay is required' if relay.nil?

              @mutex.synchronize { @relays << relay unless @relays.include?(relay) }
              relay
            end

            def drain
              relay_snapshot.sum(&:drain!)
            end

            def busy?
              relay_snapshot.any?(&:busy?)
            end

            private

            def relay_snapshot
              @mutex.synchronize { @relays.dup }
            end
          end
        end
      end
    end
  end
end
