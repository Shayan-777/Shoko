# frozen_string_literal: true

require_relative '../../../application/ports/outbound/reader_launch_state'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # In-memory runtime launch state used to pass reader warmup artifacts.
        class ReaderLaunchStateAdapter
          include Shoko::Application::Ports::Outbound::ReaderLaunchState

          def initialize
            @preloaded_document = nil
            @background_worker = nil
          end

          attr_accessor :preloaded_document, :background_worker

          def clear_preloaded_document
            @preloaded_document = nil
          end

          def clear_background_worker
            @background_worker = nil
          end
        end
      end
    end
  end
end
