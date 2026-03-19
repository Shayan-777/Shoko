# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module SelectionMouseHandlerSupport
          # Manages selection normalization and lifecycle cleanup for mouse gestures.
          module SelectionLifecycle
            private

            def handle_selection_end
              update_state_selection(@mouse_handler.selection_range)
              selection = @reader_state_reader.selection
              return unless selection

              @selected_text = extract_selected_text(selection)
              return if @selected_text && !@selected_text.strip.empty?

              @mouse_handler.reset
              @reader_session_mutator.clear_selection
            end

            def extract_selected_text(range)
              selection_service = smh_selection_service
              content_reader = smh_rendered_content_reader
              return nil unless selection_service && content_reader

              selection_service.extract_text(range, content_reader.rendered_lines)
            end

            def update_state_selection(mouse_range)
              anchor_range = anchor_range_from_mouse(mouse_range)
              if anchor_range
                @reader_session_mutator.update_reader(selection: anchor_range)
              else
                @reader_session_mutator.clear_selection
              end
            end

            def anchor_range_from_mouse(mouse_range)
              return nil unless mouse_range

              rendered = smh_rendered_content_reader&.rendered_lines
              return nil if rendered.nil? || rendered.empty?

              start_anchor = @coordinate_service.anchor_from_point(mouse_range[:start], rendered, bias: :leading)
              end_anchor = @coordinate_service.anchor_from_point(mouse_range[:end], rendered, bias: :trailing)
              return nil unless start_anchor && end_anchor

              @coordinate_service.normalize_selection_range(
                { start: start_anchor.to_h, end: end_anchor.to_h }, rendered
              )
            end
          end
        end
      end
    end
  end
end
