# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Result container for dictionary lookups
      class DictionaryResult
        attr_reader :query, :entries, :source_lang, :target_lang, :search_mode, :error_message

        def initialize(query:, entries: [], source_lang: nil, target_lang: nil, search_mode: :exact, error_message: nil)
          @query = query.to_s.freeze
          @entries = Array(entries).freeze
          @source_lang = source_lang&.to_s&.freeze
          @target_lang = target_lang&.to_s&.freeze
          @search_mode = search_mode
          @error_message = error_message&.to_s&.freeze
        end

        def found?
          entries.any? && !entries.first.empty?
        end

        def empty?
          entries.empty? || entries.all?(&:empty?)
        end

        def primary_entry
          entries.first
        end

        def entry_count
          entries.length
        end
      end
    end
  end
end
