# frozen_string_literal: true

require_relative '../../../core/models/session/reader_snapshot'
require_relative '../../../core/ports/outbound/reader_session_store'
require_relative 'reader_ui_session_registry'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-local dynamic view over the current reader snapshot.
        class ReaderSessionView
          LIVE_UI_FIELDS = ReaderUiSessionRegistry::LIVE_FIELDS

          Shoko::Core::Models::Session::ReaderSnapshotFields.each do |field|
            define_method(field) do
              current_reader.to_h[field]
            end
          end

          LIVE_UI_FIELDS.each do |field|
            define_method(field) do
              @ui_session_registry&.read(field)
            end
          end

          def initialize(reader_session_store:, ui_session_registry: nil)
            unless reader_session_store.is_a?(Shoko::Core::Ports::Outbound::ReaderSessionStore)
              raise ArgumentError, 'reader_session_store must implement Core::Ports::Outbound::ReaderSessionStore'
            end
            if !ui_session_registry.nil? && !ui_session_registry.is_a?(ReaderUiSessionRegistry)
              raise ArgumentError, 'ui_session_registry must respond to #read'
            end

            @reader_session_store = reader_session_store
            @ui_session_registry = ui_session_registry
          end

          def sidebar_visible?
            current_reader.sidebar_visible?
          end

          def loading_active?
            current_reader.loading_active?
          end

          def running?
            current_reader.running == true
          end

          def sidebar_toc_filter_active?
            current_reader.sidebar_toc_filter_active == true
          end

          def snapshot
            current_reader
          end

          private

          def current_reader
            @reader_session_store.load
          end
        end
      end
    end
  end
end
