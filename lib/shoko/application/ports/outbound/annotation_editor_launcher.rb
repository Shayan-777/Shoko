# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Boundary for opening annotation editor UI from application workflows.
        module AnnotationEditorLauncher
          def open_editor(text:, chapter_index:, annotation:)
            raise NotImplementedError, "#{self.class} must implement #open_editor"
          end
        end
      end
    end
  end
end
