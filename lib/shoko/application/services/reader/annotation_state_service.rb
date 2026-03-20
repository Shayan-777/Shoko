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

          def add(path, text_or_draft, *legacy_args)
            annotation = @core_annotation_service.add(path, coerce_draft(text_or_draft, legacy_args))
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

          def coerce_draft(text_or_draft, legacy_args)
            return text_or_draft if text_or_draft.is_a?(Shoko::Core::Models::AnnotationDraft) && legacy_args.empty?

            note, range, chapter_index, page_meta = legacy_args
            Shoko::Core::Models::AnnotationDraft.new(
              text: text_or_draft,
              note: note,
              range: range,
              chapter_index: chapter_index,
              page_meta: page_meta
            )
          end

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
