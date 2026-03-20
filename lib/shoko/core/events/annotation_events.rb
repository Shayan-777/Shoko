# frozen_string_literal: true

require_relative 'base_domain_event'

module Shoko
  module Core
    module Events
      # Domain event for annotation creation
      class AnnotationAdded < BaseDomainEvent
        required_attributes :book_path, :annotation
        typed_attributes book_path: String

        def initialize(book_path:, annotation:, **)
          super(
            aggregate_id: book_path,
            book_path: book_path,
            annotation: annotation,
            **
          )
        end

        def book_path
          get_attribute(:book_path)
        end

        def annotation
          get_attribute(:annotation)
        end
      end

      # Domain event for annotation updates
      class AnnotationUpdated < BaseDomainEvent
        required_attributes :book_path, :annotation_id, :old_note, :new_note
        typed_attributes book_path: String, annotation_id: String, old_note: String, new_note: String

        def initialize(book_path:, annotation_id:, old_note:, new_note:, **)
          super(
            aggregate_id: book_path,
            book_path: book_path,
            annotation_id: annotation_id,
            old_note: old_note,
            new_note: new_note,
            **
          )
        end

        def book_path
          get_attribute(:book_path)
        end

        def annotation_id
          get_attribute(:annotation_id)
        end

        def old_note
          get_attribute(:old_note)
        end

        def new_note
          get_attribute(:new_note)
        end
      end

      # Domain event for annotation removal
      class AnnotationRemoved < BaseDomainEvent
        required_attributes :book_path, :annotation_id
        typed_attributes book_path: String, annotation_id: String

        def initialize(book_path:, annotation_id:, annotation: nil, **)
          super(
            aggregate_id: book_path,
            book_path: book_path,
            annotation_id: annotation_id,
            annotation: annotation,
            **
          )
        end

        def book_path
          get_attribute(:book_path)
        end

        def annotation_id
          get_attribute(:annotation_id)
        end

        def annotation
          get_attribute(:annotation)
        end
      end
    end
  end
end
