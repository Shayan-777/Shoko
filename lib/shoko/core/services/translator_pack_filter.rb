# frozen_string_literal: true

require_relative '../../shared/hash_normalizer'
require 'shoko/core/services/language_directory'

module Shoko
  module Core
    module Services
      # One filtering policy shared by the pack renderer and its interaction
      # controller so visible rows, selection bounds, and activation agree.
      module TranslatorPackFilter
        module_function

        def call(entries, query)
          needle = query.to_s.strip.downcase
          return Array(entries) if needle.empty?

          Array(entries).select do |entry|
            item = Shoko::Shared::HashNormalizer.symbolize_keys(entry) || {}
            from = item[:from].to_s
            to = item[:to].to_s
            pair = "#{from}-#{to}".downcase
            names = "#{Shoko::Core::Services::LanguageDirectory.name_for(from)} " \
                    "#{Shoko::Core::Services::LanguageDirectory.name_for(to)}".downcase
            pair.include?(needle) || names.include?(needle)
          end
        end
      end
    end
  end
end
