# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'
require_relative '../../terminal/text_metrics'

module Shoko
  module Adapters::Output::Ui::Components
    # Renders the bottom status area (page info + transient message).
    class FooterComponent < BaseComponent
      def initialize(view_model_provider = nil)
        super()
        @view_model_provider = view_model_provider
        @cached_view_model = nil
      end

      def preferred_height(_available_height)
        vm = resolve_view_model
        return 0 unless vm

        renderable_page_info?(vm) ? 1 : 0
      end

      def do_render(surface, bounds)
        vm = resolve_view_model
        return unless vm

        return unless renderable_page_info?(vm)

        render_page_info(surface, bounds, vm, bounds.height)
      ensure
        @cached_view_model = nil
      end

      private

      def resolve_view_model
        return nil unless @view_model_provider

        @cached_view_model ||= @view_model_provider.call
      rescue StandardError
        nil
      end

      def renderable_page_info?(view_model)
        disallowed_modes = %i[help]
        return false if view_model.respond_to?(:mode) && disallowed_modes.include?(view_model.mode)
        return false unless view_model.respond_to?(:show_page_numbers) && view_model.show_page_numbers

        info = view_model.page_info
        info && !info.empty?
      end

      def render_page_info(surface, bounds, view_model, row)
        ui = Shoko::Adapters::Output::Ui::Constants::UI
        width = bounds.width
        info = view_model.page_info

        if view_model.view_mode == :split && info[:left]
          render_split_page_info(surface, bounds, info, width, row, ui)
        else
          render_single_page_info(surface, bounds, info, width, row, ui)
        end
      end

      def render_single_page_info(surface, bounds, info, width, row, ui_constants)
        current = info[:current].to_i
        total = info[:total].to_i
        return if current.zero? && total.zero?

        label = page_label(current, total)
        col = center_col(width, Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(label))
        write_colored(surface, bounds, row, col, label, ui_constants::COLOR_TEXT_PRIMARY)
      end

      def render_split_page_info(surface, bounds, info, width, row, ui_constants)
        left = info[:left]
        right = info[:right]
        return unless left

        left_label = page_label(left[:current].to_i, left[:total].to_i)
        left_col = quarter_center_col(width, Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(left_label),
                                      :left)
        unless left_label.empty?
          write_colored(surface, bounds, row, left_col, left_label,
                        ui_constants::COLOR_TEXT_PRIMARY)
        end

        return unless right

        right_label = page_label(right[:current].to_i, right[:total].to_i)
        right_col = quarter_center_col(width,
                                       Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(right_label), :right)
        return if right_label.empty?

        write_colored(surface, bounds, row, right_col, right_label,
                      ui_constants::COLOR_TEXT_PRIMARY)
      end

      # ----- helpers -----

      def page_label(current, total)
        total.positive? ? "#{current} / #{total}" : "Page #{current}"
      end

      def center_col(width, text_len)
        [(width - text_len) / 2, 1].max
      end

      def quarter_center_col(width, text_len, side)
        half = text_len / 2
        return [(width / 4) - half, 1].max if side == :left

        [(3 * width / 4) - half, 1].max
      end

      def write_colored(surface, bounds, row, col, text, color_prefix)
        surface.write(bounds, row, col, color_prefix + text + Terminal::ANSI::RESET)
      end
    end
  end
end
