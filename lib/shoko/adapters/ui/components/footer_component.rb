# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'
require_relative '../../../shared/terminal/text_metrics'

module Shoko
  module Adapters
    module Ui
      module Components
        # Renders the bottom status area (page info + transient message).
        class FooterComponent < BaseComponent
          PageInfoRenderContext = Data.define(:surface, :bounds, :row, :width, :ui_constants, :info)

          def initialize(view_model_provider = nil)
            super()
            @view_model_provider = view_model_provider
            @resolve_view_model = nil
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
            @resolve_view_model = nil
          end

          private

          def resolve_view_model
            return nil unless @view_model_provider

            @resolve_view_model ||= @view_model_provider.call
          end

          def renderable_page_info?(view_model)
            disallowed_modes = %i[help]
            return false if disallowed_modes.include?(view_model.mode)
            return false unless view_model.show_page_numbers

            info = view_model.page_info
            info && !info.empty?
          end

          def render_page_info(surface, bounds, view_model, row)
            context = PageInfoRenderContext.new(
              surface: surface,
              bounds: bounds,
              row: row,
              width: bounds.width,
              ui_constants: Shoko::Adapters::Ui::Constants::Ui,
              info: view_model.page_info
            )

            return render_split_page_info(context) if split_page_info?(view_model, context.info)

            render_single_page_info(context)
          end

          def split_page_info?(view_model, info)
            view_model.view_mode == :split && info[:left]
          end

          def render_single_page_info(context)
            current = context.info[:current].to_i
            total = context.info[:total].to_i
            return if current.zero? && total.zero?

            label = page_label(current, total)
            col = center_col(context.width, text_width(label))
            write_colored(context, col, label)
          end

          def render_split_page_info(context)
            left = context.info[:left]
            right = context.info[:right]
            return unless left

            left_label = page_label(left[:current].to_i, left[:total].to_i)
            render_split_page_label(context, side: :left, label: left_label)

            return unless right

            right_label = page_label(right[:current].to_i, right[:total].to_i)
            return if right_label.empty?

            render_split_page_label(context, side: :right, label: right_label)
          end

          def render_split_page_label(context, side:, label:)
            return if label.empty?

            col = quarter_center_col(context.width, text_width(label), side)
            write_colored(context, col, label)
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

          def text_width(text)
            Shoko::Shared::Terminal::TextMetrics.visible_length(text)
          end

          def write_colored(context, col, text)
            context.surface.write(
              context.bounds,
              context.row,
              col,
              context.ui_constants::COLOR_TEXT_PRIMARY + text + Shoko::Shared::Terminal::Ansi::RESET
            )
          end
        end
      end
    end
  end
end
