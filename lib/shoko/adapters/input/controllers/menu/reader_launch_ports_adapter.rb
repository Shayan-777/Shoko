# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/menu_reader_runtime'
require_relative '../../../../core/ports/outbound/menu_book_selection'
require_relative '../../../../core/ports/outbound/menu_progress_presenters'
require_relative '../../../../core/ports/outbound/menu_session_store'
require_relative '../../../../core/models/menu_book'
require_relative '../../../runtime/session_state/menu_progress_presenter'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Consolidated menu adapter for reader-launch workflow ports.
          class ReaderLaunchPortsAdapter
            include Shoko::Core::Ports::Outbound::MenuReaderRuntime
            include Shoko::Core::Ports::Outbound::MenuBookSelection
            include Shoko::Core::Ports::Outbound::MenuProgressPresenters

            def initialize(menu:, menu_session_store:, reader_controller_builder:)
              unless menu_session_store.is_a?(Shoko::Core::Ports::Outbound::MenuSessionStore)
                raise ArgumentError, 'menu_session_store must implement Core::Ports::Outbound::MenuSessionStore'
              end

              @menu = menu
              @menu_session_store = menu_session_store
              @reader_controller_builder = reader_controller_builder
            end

            def run_reader(path:, preloaded_document:, background_worker:)
              @reader_controller_builder.call(
                path,
                preloaded_document: preloaded_document,
                background_worker: background_worker
              ).run
            end

            def switch_mode(mode)
              @menu.switch_to_mode(mode)
            end

            def selected_book
              raw = @menu.selected_book_for_reader_launch
              return nil if raw.nil?

              Shoko::Core::Models::MenuBook.from_h(raw)
            end

            def filtered_books
              Array(@menu.filtered_epubs).map do |entry|
                Shoko::Core::Models::MenuBook.from_h(entry)
              end
            end

            def build
              Shoko::Adapters::Runtime::SessionState::MenuProgressPresenter.new(@menu_session_store)
            end
          end
        end
      end
    end
  end
end
