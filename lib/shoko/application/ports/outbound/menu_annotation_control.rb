# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Capability port for menu annotation selection and editing flows.
        module MenuAnnotationControl
          def move_annotation_selection(delta:)
            raise NotImplementedError, "#{self.class} must implement #move_annotation_selection"
          end

          def selected_annotation_context
            raise NotImplementedError, "#{self.class} must implement #selected_annotation_context"
          end

          def append_annotation_text(text)
            raise NotImplementedError, "#{self.class} must implement #append_annotation_text"
          end

          def delete_annotation_character
            raise NotImplementedError, "#{self.class} must implement #delete_annotation_character"
          end

          def insert_annotation_newline
            raise NotImplementedError, "#{self.class} must implement #insert_annotation_newline"
          end

          def move_annotation_cursor(direction:)
            raise NotImplementedError, "#{self.class} must implement #move_annotation_cursor"
          end

          def save_annotation
            raise NotImplementedError, "#{self.class} must implement #save_annotation"
          end

          def cancel_annotation
            raise NotImplementedError, "#{self.class} must implement #cancel_annotation"
          end
        end
      end
    end
  end
end
