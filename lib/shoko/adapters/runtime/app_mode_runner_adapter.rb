# frozen_string_literal: true

require_relative '../../application/ports/outbound/app_mode_runner'

module Shoko
  module Adapters
    module Runtime
      # Adapter bridging app mode execution to composed controllers.
      class AppModeRunnerAdapter
        include Shoko::Application::Ports::Outbound::AppModeRunner

        def initialize(reader_mode_runner:, build_menu_controller:, library_prepagination_warmup: nil)
          @reader_mode_runner = reader_mode_runner
          @build_menu_controller = build_menu_controller
          @library_prepagination_warmup = library_prepagination_warmup
        end

        def run_reader(path:)
          @reader_mode_runner.run(path: path)
        end

        def run_menu
          # Kick off opt-in library pre-pagination in the background, then ensure
          # it is cancelled when the menu exits (a book opens or the app quits) so
          # it never outlives the menu or competes with an active reader.
          @library_prepagination_warmup&.start
          @build_menu_controller.call.run
        ensure
          @library_prepagination_warmup&.cancel
        end
      end
    end
  end
end
