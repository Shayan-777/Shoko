# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/menu_reader_runtime'
require_relative '../../../../core/ports/outbound/menu_book_selection'
require_relative '../../../../core/ports/outbound/menu_progress_presenters'
require_relative '../../../../core/models/menu_book'

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

            def initialize(menu:, logger: nil)
              @menu = menu
              @logger = logger
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
