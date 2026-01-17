# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'
require_relative '../constants/ui_constants'
require_relative '../../terminal/text_metrics'

module Shoko
  module Adapters::Output::Ui::Components
    # Renders the top header row (document title).
    class HeaderComponent < BaseComponent
      include Adapters::Output::Ui::Constants::UI

      def initialize(view_model_provider = nil, theme = :dark)
        super()
        @view_model_provider = view_model_provider
        @theme = theme
      end

      def preferred_height(_available_height)
        1
      end

      def do_render(surface, bounds)
        return unless @view_model_provider

        view_model = @view_model_provider.call
        return unless view_model.respond_to?(:document_title)

        render_centered_title(surface, bounds, view_model.document_title.to_s)
      end

      private

      def render_centered_title(surface, bounds, title)
        return if title.empty?

        reset = Terminal::ANSI::RESET
        width = bounds.width
        title_width = Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(title)
        col = [(width - title_width) / 2, 1].max
        surface.write(bounds, 1, col, "#{COLOR_TEXT_PRIMARY}#{title}#{reset}")
      end
    end
  end
end
