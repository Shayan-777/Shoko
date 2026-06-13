# frozen_string_literal: true

require_relative 'base_service'
require_relative '../events/annotation_events'
require_relative '../models/annotation_draft'

module Shoko
  module Core
    module Services
      # Domain-level service for annotation persistence and domain events.
      # Uses AnnotationRepository for clean separation from infrastructure.
      #
      # This service follows hexagonal architecture principles:
      # - Persistence and domain events stay in core
      class AnnotationService < BaseService
        def initialize(annotation_repository:, domain_event_bus:, domain_event_factory:, logger: nil)
          super(logger: logger)
          @annotation_repository = annotation_repository
          @domain_event_bus = domain_event_bus
          @domain_event_factory = domain_event_factory
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
          annotation = persist_annotation(path, annotation_draft)
          publish_annotation_added(path, annotation)
          annotation
        end

        def update(path, id, note)
          old_annotation = @annotation_repository.find_by_id(path, id)
          old_note = old_annotation ? old_annotation[:note].to_s : ''

          result = @annotation_repository.update_note(path, id, note)

          @domain_event_bus.publish(
            @domain_event_factory.build(
              Events::AnnotationUpdated,
              book_path: path,
              annotation_id: id,
              old_note: old_note,
              new_note: note
            )
          )
          result
        end

        def delete(path, id)
          annotation = @annotation_repository.find_by_id(path, id)

          result = @annotation_repository.delete_by_id(path, id)

          @domain_event_bus.publish(
            @domain_event_factory.build(
              Events::AnnotationRemoved,
              book_path: path,
              annotation_id: id,
              annotation: annotation
            )
          )
          result
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

        def publish_annotation_added(path, annotation)
          @domain_event_bus.publish(
            @domain_event_factory.build(
              Events::AnnotationAdded,
              book_path: path,
              annotation: annotation
            )
          )
        end
      end
    end
  end
end
