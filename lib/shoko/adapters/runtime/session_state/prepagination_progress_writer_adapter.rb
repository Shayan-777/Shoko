# frozen_string_literal: true

require_relative '../../../application/ports/outbound/prepagination_progress_writer'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Writes library pre-pagination progress into state[:menu] using narrow,
        # field-scoped updates. Because each call only touches the prepagination
        # paths (never a full menu snapshot), it is safe to invoke from the warmup
        # worker thread while the menu renders and mutates its own state on the
        # main thread — the shared store's mutex serialises the writes.
        class PrepaginationProgressWriterAdapter
          include Shoko::Application::Ports::Outbound::PrepaginationProgressWriter

          def initialize(state)
            @state = state
          end

          def start(total:, paths:)
            @state.update(
              %i[menu prepaginate_active] => true,
              %i[menu prepaginate_total] => total.to_i,
              %i[menu prepaginate_done] => 0,
              %i[menu prepaginate_paths] => Array(paths).map(&:to_s)
            )
          end

          def report(done:)
            @state.update(%i[menu prepaginate_done] => done.to_i)
          end

          def finish
            @state.update(
              %i[menu prepaginate_active] => false,
              %i[menu prepaginate_total] => 0,
              %i[menu prepaginate_done] => 0,
              %i[menu prepaginate_paths] => []
            )
          end
        end
      end
    end
  end
end
