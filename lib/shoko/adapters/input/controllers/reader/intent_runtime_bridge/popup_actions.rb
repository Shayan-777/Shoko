# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          class IntentRuntimeBridge
            module PopupActions
              def popup_move(delta)
                key = if delta.negative?
                        Shoko::Shared::KeyDefinitions::NAVIGATION[:up].first
                      else
                        Shoko::Shared::KeyDefinitions::NAVIGATION[:down].first
                      end
                controller.handle_popup_navigation(key)
              end

              def popup_confirm
                controller.handle_popup_action_key(Shoko::Shared::KeyDefinitions::ACTIONS[:confirm].first)
              end

              def popup_cancel
                controller.handle_popup_cancel(Shoko::Shared::KeyDefinitions::ACTIONS[:cancel].first)
              end
            end
          end
        end
      end
    end
  end
end
