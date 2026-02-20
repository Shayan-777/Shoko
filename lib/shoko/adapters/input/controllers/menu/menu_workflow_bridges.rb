# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Adapter bridge for menu workflow UI/runtime operations.
          class MenuWorkflowRuntimeBridge
            def initialize(menu:, catalog:)
              @menu = menu
              @catalog = catalog
            end

            def draw_screen
              @menu.draw_screen
            end

            def refresh_scan(force:)
              @catalog.start_scan(force: force)
            end
          end
        end
      end
    end
  end
end
