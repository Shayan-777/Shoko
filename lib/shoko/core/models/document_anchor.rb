# frozen_string_literal: true

require 'shoko/shared/hash_normalizer'

module Shoko
  module Core
    module Models
      # Layout-independent anchor for a persisted annotation.
      #
      # Unlike the live selection's screen-geometry anchors (which only mean
      # anything within the frame they were captured from), a DocumentAnchor
      # survives re-wrapping: it carries the quoted text plus normalized
      # context, and is re-located against whatever the *current* layout is
      # whenever it needs to be highlighted or jumped to.
      #
      # - +quote+    — the annotated text, exactly as extracted at creation.
      #                Nil for page/chapter notes that have no quote.
      # - +prefix+   — normalized (case-folded, whitespace-stripped) text
      #                immediately before the quote, for disambiguating
      #                repeated quotes. Nil when unavailable.
      # - +suffix+   — normalized text immediately after the quote. Nil when
      #                unavailable.
      # - +position+ — 0.0..1.0 ratio of the quote's start (or, for page
      #                notes, the reading position) within the chapter's
      #                text stream. A locator hint and the page-note anchor;
      #                nil for legacy records that predate anchors.
      DocumentAnchor = Data.define(:quote, :prefix, :suffix, :position) do
        class << self
          def from_h(hash)
            return nil unless hash.is_a?(Hash)

            normalized = Shoko::Shared::HashNormalizer.symbolize_keys(hash)
            new(
              quote: presence(normalized[:quote]),
              prefix: presence(normalized[:prefix]),
              suffix: presence(normalized[:suffix]),
              position: ratio(normalized[:position])
            )
          end

          private

          def presence(value)
            text = value.to_s
            text.empty? ? nil : text
          end

          def ratio(value)
            return nil if value.nil?

            float = Float(value, exception: false)
            float&.clamp(0.0, 1.0)
          end
        end

        def quote?
          !quote.nil?
        end

        def position?
          !position.nil?
        end

        def empty?
          !quote? && !position?
        end
      end
    end
  end
end
