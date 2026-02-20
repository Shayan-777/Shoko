# frozen_string_literal: true

module Shoko
  module Core
    module Ports::Outbound
      # Port interface for dictionary database operations.
      # Adapters implementing this interface should handle word lookups
      # and translations from dictionary databases.
      #
      # @example Implementing this port
      #   class SqliteDictionaryRepository
      #     include Shoko::Core::Ports::Outbound::DictionaryRepository
      #
      #     def search(word, source_lang:, target_lang:, mode: :exact, limit: 10)
      #       # Implementation
      #     end
      #   end
      module DictionaryRepository
        # Search for a word in the dictionary
        #
        # @param word [String] The word to look up
        # @param source_lang [String] Source language code (e.g., 'de', 'en')
        # @param target_lang [String] Target language code
        # @param mode [Symbol] Search mode (:exact, :partial, :fuzzy)
        # @param limit [Integer] Maximum number of results
        # @return [Array<Hash>] Array of dictionary entry hashes
        def search(word, source_lang:, target_lang:, mode: :exact, limit: 10)
          raise NotImplementedError, "#{self.class} must implement #search"
        end

        # Perform fuzzy search to find similar words
        #
        # @param word [String] The word to search for
        # @param source_lang [String] Source language code
        # @param target_lang [String] Target language code
        # @param limit [Integer] Maximum number of results
        # @return [Array<Hash>] Array of {word:, similarity:} hashes
        def fuzzy_search(word, source_lang:, target_lang:, limit: 30)
          raise NotImplementedError, "#{self.class} must implement #fuzzy_search"
        end

        # Get available language pairs
        #
        # @return [Array<Hash>] Array of {source:, target:} hashes
        def available_language_pairs
          raise NotImplementedError, "#{self.class} must implement #available_language_pairs"
        end

        # Check if a specific language pair is available
        #
        # @param source_lang [String] Source language code
        # @param target_lang [String] Target language code
        # @return [Boolean]
        def language_pair_available?(source_lang, target_lang)
          raise NotImplementedError, "#{self.class} must implement #language_pair_available?"
        end

        # Get the database path for a language pair
        #
        # @param source_lang [String] Source language code
        # @param target_lang [String] Target language code
        # @return [String, nil] Path to database or nil if not found
        def database_path_for(source_lang, target_lang)
          raise NotImplementedError, "#{self.class} must implement #database_path_for"
        end
      end
    end
  end
end
