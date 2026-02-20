# frozen_string_literal: true

module Shoko
  module Application
    module Services
      module Reader
        # Orchestrates annotation persistence and reader-state refresh.
        class AnnotationStateService
          def initialize(core_annotation_service:, state_writer:, logger: nil)
            @core_annotation_service = core_annotation_service
            @state_writer = state_writer
            @logger = logger
          end

          def list_for_book(path)
            @core_annotation_service.list_for_book(path)
          end

          def list_all
            @core_annotation_service.list_all
          end

          def add(path, text, note, range, chapter_index, page_meta = nil)
            annotation = @core_annotation_service.add(path, text, note, range, chapter_index, page_meta)
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
            return unless @state_writer && path

            annotations = @core_annotation_service.list_for_book(path)
            @state_writer.update_reader(annotations: annotations)
          rescue StandardError => e
            @logger&.debug("annotation_state_service.refresh failed: #{e.message}")
            nil
          end
        end
      end
    end
  end
end
