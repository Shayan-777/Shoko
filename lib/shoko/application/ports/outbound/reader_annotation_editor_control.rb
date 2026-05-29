# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Capability port for the reader annotation editor surface — what's
        # left after the B.2.1 text/cursor state migration. Text edits run
        # through the editor operator service against state-store fields;
        # save and cancel are handled application-side via the annotation
        # service plus a #close_annotation_editor call here. The methods
        # below are the operations that genuinely need adapter
        # coordination: cursor movement (needs rendering width), spell
        # suggestions (needs the adapter SpellcheckCoordinator), and
        # overlay teardown (component hide + modal stack exit).
        module ReaderAnnotationEditorControl
          def move_annotation_cursor(direction:)
            raise NotImplementedError, "#{self.class} must implement #move_annotation_cursor"
          end

          def spellcheck_annotation
            raise NotImplementedError, "#{self.class} must implement #spellcheck_annotation"
          end

          def close_annotation_editor
            raise NotImplementedError, "#{self.class} must implement #close_annotation_editor"
          end
        end
      end
    end
  end
end
