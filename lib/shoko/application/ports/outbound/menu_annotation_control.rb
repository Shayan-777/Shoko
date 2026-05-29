# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Capability port for menu annotation list interactions — what's left
        # after the B.2.1 editor-text migration. Editor text/cursor edits and
        # save/cancel now run application-side over `state[:menu]` fields via
        # the editor operator service and AnnotationWorkflow. The remaining
        # methods cover annotation list-cursor reads/moves that still touch
        # adapter-owned screen-component ivars (deferred follow-up:
        # `AnnotationsScreenComponent.@selected` migration).
        module MenuAnnotationControl
          def move_annotation_selection(delta:)
            raise NotImplementedError, "#{self.class} must implement #move_annotation_selection"
          end

          def selected_annotation_context
            raise NotImplementedError, "#{self.class} must implement #selected_annotation_context"
          end

          def move_annotation_cursor(direction:)
            raise NotImplementedError, "#{self.class} must implement #move_annotation_cursor"
          end
        end
      end
    end
  end
end
