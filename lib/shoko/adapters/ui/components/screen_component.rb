# frozen_string_literal: true

require_relative 'base_component'

module Shoko
  module Presentation::Ui::Components
    # Universal screen component that can render any screen type
    # Provides a unified interface for screen rendering
    class ScreenComponent < BaseComponent
      def initialize(screen_manager)
        super()
        @screen_manager = screen_manager
      end

      def render(surface, bounds)
        @screen_manager.render_current_screen(surface, bounds)
      end

      def preferred_height(_available_height)
        :fill
      end
    end
  end
end
