# frozen_string_literal: true

require_relative '../../shared/hash_normalizer'

module Shoko
  module Core
    module Models
      # Language metadata returned by the translation backend.
      TranslationLanguage = Data.define(:code, :name, :targets) do
        # The capability shape the pickers render and the mouse handler
        # hit-tests. Accepts String or Symbol keys, since entries arrive both
        # from the backend and from persisted menu state.
        def self.normalized_entry(item)
          fields = Shoko::Shared::HashNormalizer.symbolize_keys(item) || {}
          {
            code: fields[:code].to_s,
            name: fields[:name].to_s,
            targets: Array(fields[:targets]).map(&:to_s),
          }
        end

        def initialize(code:, name:, targets: [])
          super(code: code.to_s.freeze, name: name.to_s.freeze, targets: Array(targets).map(&:to_s).freeze)
        end

        def to_h
          {
            code: code,
            name: name,
            targets: targets,
          }
        end
      end
    end
  end
end
