# frozen_string_literal: true

require_relative 'base_action'

module Shoko
  module Application
    module Actions
      # Toggle reader view between :split and :single
      class ToggleViewModeAction < BaseAction
        def apply(state)
          current = state.get(%i[config view_mode]) || :single
          new_mode = current == :split ? :single : :split

          # Update all state changes atomically
          state.update({
                         %i[config view_mode] => new_mode,
                         %i[reader last_width] => 0,
                         %i[reader last_height] => 0,
                         %i[reader dynamic_page_map] => nil,
                         %i[reader dynamic_total_pages] => 0,
                         %i[reader last_dynamic_width] => 0,
                         %i[reader last_dynamic_height] => 0,
                       })
          state.save_config if state.respond_to?(:save_config)

          new_mode
        end
      end
    end
  end
end
