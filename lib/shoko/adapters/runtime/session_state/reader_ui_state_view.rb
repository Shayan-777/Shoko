# frozen_string_literal: true

require_relative '../../../core/ports/outbound/reader_session_store'
require_relative '../../../core/ports/outbound/reader_runtime_context'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-local UI-facing view backed by reader session state and live runtime context.
        class ReaderUiStateView
          def initialize(reader_session_store:, reader_runtime_context:)
            unless reader_session_store.is_a?(Shoko::Core::Ports::Outbound::ReaderSessionStore)
              raise ArgumentError, 'reader_session_store must implement Core::Ports::Outbound::ReaderSessionStore'
            end
            unless reader_runtime_context.is_a?(Shoko::Core::Ports::Outbound::ReaderRuntimeContext)
              raise ArgumentError, 'reader_runtime_context must implement Core::Ports::Outbound::ReaderRuntimeContext'
            end

            @reader_session_store = reader_session_store
            @reader_runtime_context = reader_runtime_context
          end

          def terminal_width
            current_terminal_size.width
          end

          def terminal_height
            current_terminal_size.height
          end

          def loading_message
            current_reader.loading_message
          end

          def loading_progress
            current_reader.loading_progress
          end

          def terminal_size_changed?(width, height)
            width.to_i != current_reader.last_width.to_i || height.to_i != current_reader.last_height.to_i
          end

          private

          def current_reader
            @reader_session_store.load
          end

          def current_terminal_size
            @reader_runtime_context.terminal_size
          end
        end
      end
    end
  end
end
