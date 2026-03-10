# frozen_string_literal: true

require_relative '../../core/ports/outbound/app_mode_runner'

module Shoko
  module Adapters
    module Runtime
      # Adapter bridging app mode execution to composed controllers.
      class AppModeRunnerAdapter
        include Shoko::Core::Ports::Outbound::AppModeRunner

        def initialize(reader_mode_runner:, build_menu_controller:)
          @reader_mode_runner = reader_mode_runner
          @build_menu_controller = build_menu_controller
        end

        def run_reader(path:)
          @reader_mode_runner.run(path: path)
        end

        def run_menu
          @build_menu_controller.call.run
        end
      end
    end
  end
end
