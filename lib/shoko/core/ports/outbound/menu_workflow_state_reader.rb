# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Domain-facing reader contract for menu workflows.
        module MenuWorkflowStateReader
          def current_menu_mode
            raise NotImplementedError, "#{self.class} must implement #current_menu_mode"
          end

          def selected_library_index
            raise NotImplementedError, "#{self.class} must implement #selected_library_index"
          end

          def selected_annotation_record
            raise NotImplementedError, "#{self.class} must implement #selected_annotation_record"
          end

          def selected_annotation_book_path
            raise NotImplementedError, "#{self.class} must implement #selected_annotation_book_path"
          end

          def annotation_editor_text
            raise NotImplementedError, "#{self.class} must implement #annotation_editor_text"
          end

          def dictionary_entries
            raise NotImplementedError, "#{self.class} must implement #dictionary_entries"
          end
        end
      end
    end
  end
end
