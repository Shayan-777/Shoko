# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module UiControllerModeSwitching
          # Mode switching
          def switch_mode(mode, **)
            annotation_editor_mode =
              mode == :annotation_editor ? UIController::AnnotationEditorMode.new(self, @annotation_service, @ui_component_factory) : nil
            close_annotations_overlay unless annotation_editor_mode
            close_annotation_editor_overlay unless annotation_editor_mode
            @state_writer.update_reader(mode: mode)

            @current_mode = annotation_editor_mode&.build_component(**)

            begin
              @input_controller.activate_for_mode(mode) if @input_controller
            rescue Shoko::Error
              # If not available, ignore; read mode remains default
            end
          end

          # === UI config methods ===
          def show_help(_key = nil)
            switch_mode(:help)
          end

          def toggle_view_mode(_key = nil)
            @state_writer.toggle_view_mode
          end

          def increase_line_spacing(_key = nil)
            modes = %i[compact normal relaxed]
            current = modes.index(@config_reader.line_spacing) || 1
            return unless current < 2

            @state_writer.update_config(line_spacing: modes[current + 1])
            @state_writer.update_page(last_width: 0)
          end

          def decrease_line_spacing(_key = nil)
            modes = %i[compact normal relaxed]
            current = modes.index(@config_reader.line_spacing) || 1
            return unless current.positive?

            @state_writer.update_config(line_spacing: modes[current - 1])
            @state_writer.update_page(last_width: 0)
          end

          def toggle_page_numbering_mode(_key = nil)
            current_mode = @config_reader.page_numbering_mode
            new_mode = current_mode == :absolute ? :dynamic : :absolute
            @state_writer.update_config(page_numbering_mode: new_mode)
            set_message("Page numbering: #{new_mode}")
          end
        end
      end
    end
  end
end
