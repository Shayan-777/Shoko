# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        # Input and normalization helpers for annotation editor overlays.
        module AnnotationEditorOverlayInputSupport
          private

          def normalize_color_mode(mode)
            mode.to_s == 'light' ? :light : :dark
          end

          def backspace_key?(key)
            self.class::BACKSPACE_KEYS.include?(key)
          end

          def save_key?(key)
            self.class::SAVE_KEYS.include?(key)
          end

          def cancel_key?(key)
            Shared::KeyDefinitions::ACTIONS[:cancel].include?(key)
          end

          def printable?(key)
            return false unless key.is_a?(String)
            return false if key.length != 1

            codepoint = key.ord
            return false if codepoint < 0x20
            return false if codepoint == 0x7F
            return false if codepoint.between?(0x80, 0x9F)

            true
          end

          def symbolize_hash(value)
            return {} unless value.is_a?(Hash)

            value.transform_keys do |key|
              key.is_a?(String) ? key.to_sym : key
            end
          end
        end
      end
    end
  end
end
