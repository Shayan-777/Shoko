# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Adapter runtime contract for menu intent handling.
        module MenuIntentRuntime
          def activate_mode(mode)
            raise NotImplementedError, "#{self.class} must implement #activate_mode"
          end

          def browse_items_count
            raise NotImplementedError, "#{self.class} must implement #browse_items_count"
          end

          def library_items_count
            raise NotImplementedError, "#{self.class} must implement #library_items_count"
          end

          def selected_library_target_path
            raise NotImplementedError, "#{self.class} must implement #selected_library_target_path"
          end

          def selected_download_book
            raise NotImplementedError, "#{self.class} must implement #selected_download_book"
          end

          def move_annotation_selection(delta)
            raise NotImplementedError, "#{self.class} must implement #move_annotation_selection"
          end

          def selected_annotation_context
            raise NotImplementedError, "#{self.class} must implement #selected_annotation_context"
          end

          def annotation_editor_insert_text(text)
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_insert_text"
          end

          def annotation_editor_backspace
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_backspace"
          end

          def annotation_editor_newline
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_newline"
          end

          def annotation_editor_move(direction)
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_move"
          end

          def annotation_editor_save
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_save"
          end

          def annotation_editor_cancel
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_cancel"
          end

          def quit_application(code:, message:)
            raise NotImplementedError, "#{self.class} must implement #quit_application"
          end
        end
      end
    end
  end
end
