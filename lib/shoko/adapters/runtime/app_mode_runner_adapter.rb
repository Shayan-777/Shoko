# frozen_string_literal: true

require_relative '../../core/ports/outbound/app_mode_runner'

module Shoko
  module Adapters
    module Runtime
      # Adapter bridging app mode execution to composed controllers.
      class AppModeRunnerAdapter
        include Shoko::Core::Ports::Outbound::AppModeRunner

        def initialize(build_reader_controller:, build_menu_controller:)
          @build_reader_controller = build_reader_controller
          @build_menu_controller = build_menu_controller
        end

        def run_reader(path:)
          @build_reader_controller.call(path).run
        end

        def run_menu
          @build_menu_controller.call.run
        end
      end
    end
  end
end
