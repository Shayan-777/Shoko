# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Capability port for translator-editor interactions that need rendered
        # geometry. Text/cursor edits run application-side over `state[:menu]`
        # translator_input_* fields via the shared editor operator, but cursor
        # *movement* across visual (wrapped) lines depends on the panel width
        # known only to the adapter-owned translator screen component — so it is
        # delegated here, mirroring MenuAnnotationControl#move_annotation_cursor.
        module MenuTranslatorControl
          def move_translator_cursor(direction:)
            raise NotImplementedError, "#{self.class} must implement #move_translator_cursor"
          end
        end
      end
    end
  end
end
