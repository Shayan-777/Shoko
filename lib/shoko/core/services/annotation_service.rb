# frozen_string_literal: true

require_relative 'base_service'
require_relative '../models/annotation_draft'

module Shoko
  module Core
    module Services
      # Domain-level service for annotation persistence.
      # Uses AnnotationRepository for clean separation from infrastructure.
      class AnnotationService < BaseService
        def initialize(annotation_repository:, logger: nil)
          super(logger: logger)
          @annotation_repository = annotation_repository
        end

        def list_for_book(path)
          return [] unless path && !path.to_s.empty?

          @annotation_repository.find_by_book_path(path)
        end

        def list_all
          @annotation_repository.find_all
        end

        def add(path, draft)
          annotation_draft = coerce_draft(draft)
          persist_annotation(path, annotation_draft)
        end

        def update(path, id, note)
          @annotation_repository.update_note(path, id, note)
        end

        def delete(path, id)
          @annotation_repository.delete_by_id(path, id)
        end

        private

        def coerce_draft(draft)
          return draft if draft.is_a?(Shoko::Core::Models::AnnotationDraft)

          raise ArgumentError, "draft must be #{Shoko::Core::Models::AnnotationDraft}"
        end

        def persist_annotation(path, draft)
          @annotation_repository.add_for_book(
            path,
            text: draft.text,
            note: draft.note,
            anchor: draft.anchor_hash,
            chapter_index: draft.chapter_index
          )
        end
      end
    end
  end
end
