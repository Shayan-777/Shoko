# frozen_string_literal: true

require_relative 'base_service'
require_relative '../events/annotation_events'
require_relative '../ports/state_writer'

module Shoko
  module Core
    module Services
      # Domain-level service for annotation persistence and state updates.
      # Uses AnnotationRepository for clean separation from infrastructure.
      #
      # This service follows hexagonal architecture principles:
      # - State writing goes through StateWriter port
      class AnnotationService < BaseService
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

          @domain_event_bus.publish(Events::AnnotationAdded.new(
                                      book_path: path,
                                      annotation: annotation
                                    ))

          notify_updated(path)
          annotation
        end

        def update(path, id, note)
          old_note = ''
          if @annotation_repository.respond_to?(:find_by_id)
            old_annotation = @annotation_repository.find_by_id(path, id)
            old_note = old_annotation ? old_annotation['note'] : ''
          end

          result = @annotation_repository.update_note(path, id, note)

          @domain_event_bus.publish(Events::AnnotationUpdated.new(
                                      book_path: path,
                                      annotation_id: id,
                                      old_note: old_note,
                                      new_note: note
                                    ))

          notify_updated(path)
          result
        end

        def delete(path, id)
          annotation = @annotation_repository.find_by_id(path, id) if @annotation_repository.respond_to?(:find_by_id)

          result = @annotation_repository.delete_by_id(path, id)

          @domain_event_bus.publish(Events::AnnotationRemoved.new(
                                      book_path: path,
                                      annotation_id: id,
                                      annotation: annotation
                                    ))

          notify_updated(path)
          result
        end

        protected

        def required_dependencies
          %i[annotation_repository domain_event_bus state_writer]
        end

        def setup_service_dependencies
          @annotation_repository = resolve(:annotation_repository)
          @domain_event_bus = resolve(:domain_event_bus)
          @state_writer = resolve(:state_writer)
        end

        private

        def notify_updated(path)
          return unless @state_writer && path

          annotations = list_for_book(path)
          @state_writer.update_reader(annotations: annotations)
        rescue StandardError
          # Best-effort state refresh; persistence already succeeded
          nil
        end
      end
    end
  end
end
