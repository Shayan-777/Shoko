# frozen_string_literal: true

module Shoko
  module Core
    module Models
      # Language metadata returned by the translation backend.
      TranslationLanguage = Data.define(:code, :name, :targets) do
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
