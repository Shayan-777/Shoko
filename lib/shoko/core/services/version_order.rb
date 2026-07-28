# frozen_string_literal: true

module Shoko
  module Core
    module Services
      # Dependency-free ordering for dotted release versions and natural
      # prerelease suffixes (for example 1.0a2 < 1.0a10 < 1.0).
      module VersionOrder
        module_function

        def compare(left, right)
          left_numbers, left_suffix = components(left)
          right_numbers, right_suffix = components(right)
          numeric = compare_numbers(left_numbers, right_numbers)
          return numeric unless numeric.zero?
          return 0 if left_suffix == right_suffix
          return 1 if left_suffix.empty?
          return -1 if right_suffix.empty?

          prerelease_tokens(left_suffix) <=> prerelease_tokens(right_suffix)
        end

        def newer?(candidate, installed)
          compare(candidate, installed).positive?
        end

        def components(version)
          match = version.to_s.strip.match(/\A(\d+(?:\.\d+)*)(.*)\z/)
          return [[], version.to_s.downcase] unless match

          [match[1].split('.').map(&:to_i), match[2].to_s.downcase]
        end
        private_class_method :components

        def compare_numbers(left, right)
          length = [left.length, right.length].max
          length.times do |index|
            comparison = left.fetch(index, 0) <=> right.fetch(index, 0)
            return comparison unless comparison.zero?
          end
          0
        end
        private_class_method :compare_numbers

        def prerelease_tokens(suffix)
          suffix.scan(/\d+|[^\d]+/).map do |token|
            token.match?(/\A\d+\z/) ? [1, token.to_i] : [0, token]
          end
        end
        private_class_method :prerelease_tokens
      end
    end
  end
end
