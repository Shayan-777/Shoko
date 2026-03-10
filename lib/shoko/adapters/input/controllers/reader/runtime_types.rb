# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Shared mutable runtime state holders for the reader controller.
          module RuntimeTypes
            Context = Struct.new(:path, :doc, :metrics_start_time, keyword_init: true)
            Services = Struct.new(:page_calculator, :terminal_service, :clipboard_service, :instrumentation,
                                  keyword_init: true)
            ControllerRefs = Struct.new(:ui_controller, :state_controller, :input_controller, keyword_init: true)
            Coordinators = Struct.new(:lifecycle, :pagination_coordinator, :render_coordinator, keyword_init: true)
            RuntimeComponents = Struct.new(:ui_controller, :state_controller, :input_controller,
                                           :pagination_coordinator, :render_coordinator, keyword_init: true)
          end
        end
      end
    end
  end
end
