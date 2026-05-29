# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          class IntentRuntimeBridge
            # Maps reader intents onto reader-mode overlays, pagination, and exit commands.
            module ReaderActions
              def show_annotations_overlay
                controller.open_annotations
              end

              def rebuild_pagination
                controller.rebuild_pagination
              end

              def clear_pagination_cache
                controller.invalidate_pagination_cache
              end

              def return_to_menu
                controller.quit_to_menu
              end

              def quit_application
                controller.quit_application
              end
            end
          end
        end
      end
    end
  end
end
