# frozen_string_literal: true

require_relative 'dictionary_entry'

module Shoko
  module Core
    module Models
      # Immutable result container for dictionary lookups.
      DictionaryResult = Data.define(:query, :entries, :source_lang, :target_lang, :search_mode, :error_message) do
        def initialize(query:, entries: [], source_lang: nil, target_lang: nil, search_mode: :exact,
                       error_message: nil)
          super(
            query: immutable_text(query),
            entries: immutable_entries(entries),
            source_lang: immutable_optional_text(source_lang),
            target_lang: immutable_optional_text(target_lang),
            search_mode: normalize_search_mode(search_mode),
            error_message: immutable_optional_text(error_message)
          )
        end

        def found? = entries.any? && !entries.first.empty?

        def empty? = entries.empty? || entries.all?(&:empty?)

        def primary_entry = entries.first

        def entry_count = entries.length

        private

        def immutable_text(value) = value.to_s.dup.freeze

        def immutable_optional_text(value) = value.nil? ? nil : immutable_text(value)

        def immutable_entries(values)
          Array(values).map do |entry|
            unless entry.is_a?(Shoko::Core::Models::DictionaryEntry)
              raise ArgumentError, "entries must contain DictionaryEntry values, got #{entry.class}"
            end

            entry
          end.freeze
        end

        def normalize_search_mode(value)
          value.to_sym
        rescue NoMethodError
          raise ArgumentError, "search_mode must be symbol-like, got #{value.class}"
        end
      end
    end
  end
end
