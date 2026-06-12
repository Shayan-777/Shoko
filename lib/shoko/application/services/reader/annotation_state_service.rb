# frozen_string_literal: true

require_relative '../../../core/models/annotation_draft'

module Shoko
  module Application
    module Services
      module Reader
        # Orchestrates annotation persistence and reader-state refresh.
        class AnnotationStateService
          def initialize(core_annotation_service:, reader_session_store:, logger: nil)
            @core_annotation_service = core_annotation_service
            @reader_session_store = reader_session_store
            @logger = logger
          end

          def list_for_book(path)
            @core_annotation_service.list_for_book(path)
          end

          def list_all
            @core_annotation_service.list_all
          end

          def add(path, draft)
            unless draft.is_a?(Shoko::Core::Models::AnnotationDraft)
              raise ArgumentError, "draft must be #{Shoko::Core::Models::AnnotationDraft}"
            end

            annotation = @core_annotation_service.add(path, draft)
            refresh_annotations_for(path)
            annotation
          end

          def update(path, id, note)
            result = @core_annotation_service.update(path, id, note)
            refresh_annotations_for(path)
            result
          end

          def delete(path, id)
            result = @core_annotation_service.delete(path, id)
            refresh_annotations_for(path)
            result
          end

          private

          def refresh_annotations_for(path)
            return unless @reader_session_store && path

            annotations = @core_annotation_service.list_for_book(path)
            snapshot = @reader_session_store.load
            @reader_session_store.save(snapshot.with(annotations: annotations))
          end
        end
      end
    end
  end
end
