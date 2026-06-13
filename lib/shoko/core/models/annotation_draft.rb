# frozen_string_literal: true

require_relative 'document_anchor'

module Shoko
  module Core
    module Models
      # Immutable annotation creation payload shared across application and
      # storage seams. The +anchor+ is a layout-independent DocumentAnchor
      # (quote + context, or a position ratio) captured when the annotation is
      # created; it is what re-locates the annotation after re-wrapping, not a
      # screen-geometry range.
      AnnotationDraft = Data.define(:text, :note, :anchor, :chapter_index) do
        def anchor_hash
          anchor.is_a?(Shoko::Core::Models::DocumentAnchor) ? anchor.to_h : anchor
        end
      end
    end
  end
end
