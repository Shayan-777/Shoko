# frozen_string_literal: true

require_relative '../../shared/hash_normalizer'

module Shoko
  module Core
    module Models
      # Value object representing a dictionary lookup result entry.
      # Contains word, senses, translations, and metadata.
      class DictionaryEntry
        ATTRIBUTES = %i[
          word
          language
          lexentry
          senses
          translations
          score
          importance
        ].freeze

        attr_reader(*ATTRIBUTES)

        def initialize(word:, language: nil, lexentry: nil, senses: [], translations: [], score: 0.0, importance: 0.0)
          @word = word.to_s.freeze
          @language = language&.to_s&.freeze
          @lexentry = lexentry&.to_s&.freeze
          @senses = Array(senses).map(&:freeze).freeze
          @translations = Array(translations).map(&:freeze).freeze
          @score = score.to_f
          @importance = importance.to_f
        end

        def self.from_hash(hash)
          return nil unless hash.is_a?(Hash)

          new(
            word: extract(hash, :written_rep) || extract(hash, :word),
            language: extract(hash, :language),
            lexentry: extract(hash, :lexentry),
            senses: parse_list(extract(hash, :sense_list) || extract(hash, :sense)),
            translations: parse_list(extract(hash, :trans_list) || extract(hash, :translations)),
            score: extract(hash, :score, 0.0),
            importance: extract(hash, :importance, 0.0)
          )
        end

        def self.extract(hash, key, default = nil)
          normalized = Shoko::Shared::HashNormalizer.symbolize_keys(hash) || {}
          normalized.key?(key) ? normalized[key] : default
        end
        private_class_method :extract

        def self.parse_list(value)
          return [] if value.nil?
          return value if value.is_a?(Array)

          value.to_s.split('|').map(&:strip).reject(&:empty?)
        end
        private_class_method :parse_list

        def to_h
          {
            word: word,
            language: language,
            lexentry: lexentry,
            senses: senses,
            translations: translations,
            score: score,
            importance: importance,
          }
        end

        def empty?
          senses.empty? && translations.empty?
        end

        def primary_sense
          senses.first
        end

        def primary_translation
          translations.first
        end

        # Group senses by part of speech if they contain POS markers
        def senses_grouped
          senses.each_with_object({}) do |sense, groups|
            # Try to extract POS from sense text (e.g., "[noun]" or "n.")
            pos = extract_part_of_speech(sense)
            (groups[pos] ||= []) << sense
          end
        end

        private

        def extract_part_of_speech(sense)
          # Common POS patterns in dictionary senses
          case sense.downcase
          when /\b(noun|n\.)\b/ then 'Noun'
          when /\b(verb|v\.)\b/ then 'Verb'
          when /\b(adjective|adj\.)\b/ then 'Adjective'
          when /\b(adverb|adv\.)\b/ then 'Adverb'
          when /\b(preposition|prep\.)\b/ then 'Preposition'
          when /\b(conjunction|conj\.)\b/ then 'Conjunction'
          when /\b(interjection|interj\.)\b/ then 'Interjection'
          when /\b(pronoun|pron\.)\b/ then 'Pronoun'
          when /\b(article|art\.)\b/ then 'Article'
          else 'Definition'
          end
        end
      end

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

      # Fuzzy search result with similarity score
      class FuzzyMatch
        attr_reader :word, :similarity

        def initialize(word:, similarity:)
          @word = word.to_s.freeze
          @similarity = similarity.to_f
        end

        def high_confidence?
          similarity >= 0.8
        end

        def medium_confidence?
          similarity >= 0.6 && similarity < 0.8
        end

        def low_confidence?
          similarity < 0.6
        end
      end
    end
  end
end
