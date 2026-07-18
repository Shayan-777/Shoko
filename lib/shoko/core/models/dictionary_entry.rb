# frozen_string_literal: true

require_relative '../../shared/hash_normalizer'

module Shoko
  module Core
    module Models
      # Value object representing a dictionary lookup result entry.
      # Contains word, senses, translations, and metadata.
      class DictionaryEntry
        ATTRIBUTES = %i[word language lexentry senses translations score importance].freeze
        PART_OF_SPEECH_PATTERNS = {
          'Noun' => /\b(noun|n\.)\b/,
          'Verb' => /\b(verb|v\.)\b/,
          'Adjective' => /\b(adjective|adj\.)\b/,
          'Adverb' => /\b(adverb|adv\.)\b/,
          'Preposition' => /\b(preposition|prep\.)\b/,
          'Conjunction' => /\b(conjunction|conj\.)\b/,
          'Interjection' => /\b(interjection|interj\.)\b/,
          'Pronoun' => /\b(pronoun|pron\.)\b/,
          'Article' => /\b(article|art\.)\b/,
        }.freeze

        attr_reader(*ATTRIBUTES)

        def initialize(word:, language: nil, lexentry: nil, senses: [], translations: [], score: 0.0, importance: 0.0)
          @word = word.to_s.freeze
          @language = language&.to_s&.freeze
          @lexentry = lexentry&.to_s&.freeze
          @senses = Array(senses).map(&:freeze).freeze
          @translations = Array(translations).map(&:freeze).freeze
          @score = score.to_f
          @importance = importance.to_f
          # Born frozen: entries are placed into the state tree, whose value
          # contract admits opaque objects only when they are immutable.
          freeze
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
          normalized = sense.to_s.downcase
          PART_OF_SPEECH_PATTERNS.each do |label, pattern|
            return label if pattern.match?(normalized)
          end
          'Definition'
        end
      end
    end
  end
end
