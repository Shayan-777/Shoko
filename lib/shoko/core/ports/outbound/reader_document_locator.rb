# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      module Outbound
        # Port interface for resolving canonical reader document paths and
        # matching reader documents against target paths.
        module ReaderDocumentLocator
          def canonical_reader_path(path)
            raise NotImplementedError, "#{self.class} must implement #canonical_reader_path"
          end

          def document_matches_path?(document, target_path)
            raise NotImplementedError, "#{self.class} must implement #document_matches_path?"
          end

          def resolve_source_path(path)
            raise NotImplementedError, "#{self.class} must implement #resolve_source_path"
          end
        end
      end
    end
  end
end
