# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Boundary for reading selected annotation + owning book path.
        module AnnotationSelectionReader
          # @return [Array<(Hash,nil),(String,nil)>] [annotation, book_path]
          def selected_annotation_and_path
            raise NotImplementedError, "#{self.class} must implement #selected_annotation_and_path"
          end
        end
      end
    end
  end
end
