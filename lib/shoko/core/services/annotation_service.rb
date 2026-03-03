# frozen_string_literal: true

require_relative 'base_service'
require_relative '../events/annotation_events'

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

        def add(path, text, note, range, chapter_index, page_meta = nil)
          annotation = @annotation_repository.add_for_book(
            path,
            text: text,
            note: note,
            range: range,
            chapter_index: chapter_index,
            page_meta: page_meta
          )

          @domain_event_bus.publish(
            @domain_event_factory.build(
              Events::AnnotationAdded,
              book_path: path,
              annotation: annotation
            )
          )
          annotation
        end

        def update(path, id, note)
          old_note = ''
          old_annotation = @annotation_repository.find_by_id(path, id)
          old_note = old_annotation ? old_annotation['note'] : ''

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
      end
    end
  end
end
