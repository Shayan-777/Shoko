# frozen_string_literal: true

require_relative '../../shared/hash_normalizer'

module Shoko
  module Core
    # Immutable dictionary-domain value objects.
    module Models
      # Immutable value object representing a dictionary lookup result entry.
      DictionaryEntry = Data.define(:word, :language, :lexentry, :senses, :translations, :score, :importance) do
        def initialize(word:, language: nil, lexentry: nil, senses: [], translations: [], score: 0.0, importance: 0.0)
          super(
            word: immutable_text(word),
            language: immutable_optional_text(language),
            lexentry: immutable_optional_text(lexentry),
            senses: immutable_text_list(senses),
            translations: immutable_text_list(translations),
            score: score.to_f,
            importance: importance.to_f
          )
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

        def empty? = senses.empty? && translations.empty?

        def primary_sense = senses.first

        def primary_translation = translations.first

        def senses_grouped
          senses.each_with_object({}) do |sense, groups|
            pos = extract_part_of_speech(sense)
            (groups[pos] ||= []) << sense
          end
        end

        private

        def immutable_text(value) = value.to_s.dup.freeze

        def immutable_optional_text(value) = value.nil? ? nil : immutable_text(value)

        def immutable_text_list(values)
          Array(values).map { |value| immutable_text(value) }.freeze
        end

        def extract_part_of_speech(sense)
          normalized = sense.to_s.downcase
          self.class::PART_OF_SPEECH_PATTERNS.each do |label, pattern|
            return label if pattern.match?(normalized)
          end
          'Definition'
        end
      end

      DictionaryEntry.const_set(:ATTRIBUTES, DictionaryEntry.members.freeze)
      DictionaryEntry.const_set(
        :PART_OF_SPEECH_PATTERNS,
        {
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
      )
    end
  end
end
