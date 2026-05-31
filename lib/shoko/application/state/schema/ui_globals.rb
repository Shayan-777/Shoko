# frozen_string_literal: true

module Shoko
  module Application
    module State
      module Schema
        # Schema fragment for the global UI slice (`state[:ui]`).
        #
        # Holds the terminal dimensions (the UI's frame-of-reference) and
        # the canonical loading mirror used by the render coordinator. The
        # reader-view adapter mirrors loading_* into `state[:reader]` for
        # convenient projection.
        #
        # Design note: these fields — terminal dimensions especially — are
        # UI presentation concerns, and they live in the single
        # application-owned state store by design. The reader uses one
        # central, schema-partitioned store as its source of truth (the
        # "single store" pattern); UI-presentation state belongs to the
        # view/UI-designated fragments of that store (this one and
        # `ReaderView`), not a separate per-layer store. The store remains
        # the one schema authority; the UI writes these fields and observes
        # them through outbound ports.
        module UiGlobals
          PARTITION = :ui

          FIELDS = %i[
            terminal_width
            terminal_height
            loading_active
            loading_message
            loading_progress
          ].freeze

          DEFAULTS = {
            terminal_width: 80,
            terminal_height: 24,
            loading_active: false,
            loading_message: nil,
            loading_progress: nil,
          }.freeze

          module_function

          def contribute(_context = {})
            { PARTITION => DEFAULTS.dup }
          end
        end
      end
    end
  end
end
