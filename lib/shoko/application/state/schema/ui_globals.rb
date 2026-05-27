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
        # NOTE (Option-A compromise): the fields here — terminal
        # dimensions especially — are conceptually UI presentation. They
        # live under `Application::State::Schema` because the unified
        # state store is application-hosted and needs a single schema
        # authority to initialise its hash. Option-B work is to move this
        # fragment into `Adapters::Ui::State::Schema` once the store is
        # physically decomposed per layer.
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
