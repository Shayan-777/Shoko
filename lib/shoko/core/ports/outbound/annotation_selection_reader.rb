# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Boundary for reading selected annotation context.
        module AnnotationSelectionReader
          # @return [Core::Models::AnnotationSelection, nil]
          def selected_annotation
            raise NotImplementedError, "#{self.class} must implement #selected_annotation"
          end
        end
      end
    end
  end
end
