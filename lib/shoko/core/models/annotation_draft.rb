# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Immutable annotation creation payload shared across application and storage seams.
      AnnotationDraft = Data.define(:text, :note, :range, :chapter_index, :page_meta)
    end
  end
end
