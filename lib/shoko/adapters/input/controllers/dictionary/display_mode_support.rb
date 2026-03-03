# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Dictionary
          # Display mode resolution for dictionary panel/popup rendering.
          module DisplayModeSupport
            def determine_dictionary_display_mode(terminal_width, terminal_height)
              min_terminal = dictionary_panel_min_terminal_width
              return :popup if terminal_width < min_terminal

              available_right = dictionary_available_right_space(terminal_width, terminal_height)
              min_width = dictionary_panel_min_width
              return :panel if available_right >= min_width

              :popup
            rescue Shoko::Error => e
              @logger&.debug("DictionaryController.determine_dictionary_display_mode failed: #{e.message}")
              :popup
            end

            private

            def dictionary_available_right_space(terminal_width, terminal_height)
              sidebar_width = sidebar_width_for(terminal_width, terminal_height)
              main_width = terminal_width - sidebar_width
              return 0 if main_width <= 0

              layout_service = @layout_service
              view_mode = @config_reader.view_mode || :single
              col_width, = layout_service&.calculate_metrics(main_width, terminal_height, view_mode)
              col_width ||= view_mode == :split ? (main_width / 2) : main_width

              content_right_edge = if view_mode == :split
                                     left_start = @layout_metrics.split_left_margin + 1
                                     right_start = left_start + col_width + @layout_metrics.split_column_gap
                                     right_start + col_width - 1
                                   else
                                     col_start = [(main_width - col_width) / 2, 1].max
                                     col_start + col_width - 1
                                   end

              absolute_right_edge = sidebar_width + content_right_edge
              [terminal_width - absolute_right_edge, 0].max
            end

            def sidebar_width_for(terminal_width, terminal_height)
              return 0 unless @sidebar_state.sidebar_visible?

              sidebar_bounds = @reader_controller&.render_coordinator&.sidebar_bounds(terminal_width, terminal_height)
              return sidebar_bounds.width if sidebar_bounds&.width

              0
            rescue Shoko::Error => e
              @logger&.debug("DictionaryController.sidebar_width_for failed: #{e.message}")
              0
            end
          end
        end
      end
    end
  end
end
