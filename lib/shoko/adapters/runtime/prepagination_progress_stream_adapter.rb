# frozen_string_literal: true

require 'json'
require_relative '../../application/ports/outbound/prepagination_progress_writer'

module Shoko
  module Adapters
    module Runtime
      # Progress writer used inside the pre-pagination batch child process:
      # emits one JSON line per progress event on the given stream so the
      # parent menu process can mirror them into its toast/list state.
      class PrepaginationProgressStreamAdapter
        include Shoko::Application::Ports::Outbound::PrepaginationProgressWriter

        def initialize(output: $stdout)
          @output = output
        end

        def start(total:, paths:)
          emit(event: 'start', total: total, paths: paths)
        end

        def report(done:)
          emit(event: 'report', done: done)
        end

        def finish
          emit(event: 'finish')
        end

        private

        def emit(payload)
          @output.puts(JSON.generate(payload))
          @output.flush
        rescue IOError, SystemCallError
          # The parent closed the pipe (cancelled batch): progress has nowhere
          # to go, which is fine — pagination itself keeps its value.
          nil
        end
      end
    end
  end
end
