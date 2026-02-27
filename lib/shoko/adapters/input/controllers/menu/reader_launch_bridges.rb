# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/menu_reader_runtime'
require_relative '../../../../core/ports/outbound/menu_book_selection'
require_relative '../../../../core/ports/outbound/menu_progress_presenters'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Adapter bridge for menu-driven reader runtime operations.
          class ReaderLaunchRuntimeBridge
            include Shoko::Core::Ports::Outbound::MenuReaderRuntime

            def initialize(menu:, reader_controller_builder:)
              @menu = menu
              @reader_controller_builder = reader_controller_builder
            end

            def run_reader(path:, preloaded_document:, background_worker:)
              @reader_controller_builder.call(
                path,
                preloaded_document: preloaded_document,
                background_worker: background_worker
              ).run
            end

            def draw_screen
              @menu.draw_screen
            end

            def switch_mode(mode)
              @menu.switch_to_mode(mode)
            end
          end

          # Adapter bridge for selected/filtered menu books.
          class ReaderLaunchBookSelectionBridge
            include Shoko::Core::Ports::Outbound::MenuBookSelection

            def initialize(selected_book_reader:, filtered_books_reader:)
              @selected_book_reader = selected_book_reader
              @filtered_books_reader = filtered_books_reader
            end

            def selected_book
              @selected_book_reader.call
            rescue StandardError
              nil
            end

            def filtered_books
              Array(@filtered_books_reader.call)
            rescue StandardError
              []
            end
          end

          # Adapter bridge for progress presenter construction.
          class ReaderLaunchProgressPresenters
            include Shoko::Core::Ports::Outbound::MenuProgressPresenters

            def initialize(presenter_builder:)
              @presenter_builder = presenter_builder
            end

            def build
              @presenter_builder.call
            end
          end
        end
      end
    end
  end
end
