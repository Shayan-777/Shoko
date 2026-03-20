# frozen_string_literal: true

require_relative 'wrapped_result_search_index'
require_relative 'wrapped_result_matching'

module Shoko
  module Adapters
    module Input
      module Controllers
        class InBookSearchController
          class ResultNavigator
            # Resolves wrapped search snippets back to stable chapter line offsets.
            module WrappedResultLocator
              include WrappedResultSearchIndex
              include WrappedResultMatching

              private

              def resolve_result_line_offset(result_entry, chapter_index:)
                fallback = integer_result_value(result_entry, :line_index) || 0
                direct_wrapped = direct_wrapped_result_line_offset(result_entry,
                                                                   chapter_index: chapter_index,
                                                                   fallback: fallback)
                return direct_wrapped unless direct_wrapped.nil?
                return fallback unless @page_calculator

                chapter_index_data = chapter_wrapped_search_index(@page_calculator, chapter_index)
                return fallback unless chapter_index_data

                locate_wrapped_line_offset(chapter_index_data, result_entry) || fallback
              end

              def direct_wrapped_result_line_offset(result_entry, chapter_index:, fallback:)
                return nil unless wrapped_search_result?(result_entry)
                return nil unless @page_calculator

                page_hint = integer_result_value(result_entry, :page_index)
                hinted_page = resolve_result_page(@page_calculator, page_hint)
                return fallback if valid_result_page?(hinted_page, chapter_index: chapter_index, line_offset: fallback)

                chapter_pages = Array(@page_calculator.pages_data).select do |page|
                  result_page_chapter_index(page) == chapter_index.to_i
                end
                return fallback if chapter_pages.any? { |page| page_contains_line_offset?(page, fallback) }

                nil
              end
            end
          end
        end
      end
    end
  end
end
