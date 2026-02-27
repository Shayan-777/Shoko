# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      class BookCachePipeline
        # Validates cached payload completeness.
        class CacheIntegrityChecker
          def initialize(cache:, payload:)
            @cache = cache
            @payload = payload
          end

          def incomplete?
            chapters = Array(book&.chapters)
            return true if chapters.empty? || chapters.any?(&:nil?)

            !@cache.chapters_complete?(chapters.length, generation: chapters_generation)
          rescue StandardError
            true
          end

          private

          def book
            @payload&.book
          end

          def chapters_generation
            book&.chapters_generation
          rescue NoMethodError
            nil
          end
        end

        private_constant :CacheIntegrityChecker
      end
    end
  end
end
