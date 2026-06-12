# frozen_string_literal: true

require 'shoko/shared/hash_normalizer'

module Shoko
  module Application
    module Services
      module Pagination
        module Internal
          # Maintains chapter/page indexes and maps persisted line offsets back to page indices.
          class RestoreMappingService
            def initialize
              reset!
            end

            def reset!
              @chapter_page_index = Hash.new { |hash, key| hash[key] = [] }
            end

            def rebuild!(pages)
              reset!
              Array(pages).each_with_index do |page, index|
                normalized = normalize_page(page)
                next unless normalized

                chapter_index = normalized[:chapter_index].to_i
                @chapter_page_index[chapter_index] << normalized.merge(global_index: index)
              end

              @chapter_page_index.each_value do |entries|
                entries.sort_by! { |page| page[:end_line].to_i }
              end
            end

            def find_page_index(chapter_index, line_offset)
              pages = @chapter_page_index[chapter_index]
              return 0 unless pages && !pages.empty?

              match = pages.bsearch { |page| line_offset <= page[:end_line].to_i }
              return match[:global_index] if match && match[:global_index]

              pages.last[:global_index] || 0
            end

            def apply_pending_precise_restore!(reader_state_reader)
              pending = normalize_page(reader_state_reader.pending_progress)
              return unless pending && pending[:line_offset]

              chapter_index = pending[:chapter_index] || reader_state_reader.current_chapter
              page_index = find_page_index(chapter_index, pending[:line_offset].to_i)
              payload = { clear_pending_progress: true }
              payload[:current_page_index] = page_index if page_index && page_index >= 0
              payload
            end

            private

            def normalize_page(page)
              return nil unless page.is_a?(Hash)

              Shoko::Shared::HashNormalizer.deep_symbolize(page)
            end
          end
        end
      end
    end
  end
end
