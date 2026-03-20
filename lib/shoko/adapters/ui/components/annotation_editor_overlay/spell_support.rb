# frozen_string_literal: true

require_relative '../base_component'
require_relative 'spell_support/popup_rendering'
require_relative 'spell_support/word_analysis'

module Shoko
  module Adapters
    module Ui
      module Components
        class AnnotationEditorOverlayComponent < BaseComponent
          # Spell-suggestion state and popup rendering for the annotation editor.
          module SpellSupport
            include PopupRendering
            include WordAnalysis

            def show_spell_suggestions(target, suggestions, scope_key: nil, scope_label: nil, can_cycle: false)
              normalized_target = normalize_spell_target(target)
              normalized_suggestions = normalize_spell_suggestions(suggestions)

              if normalized_target.nil?
                dismiss_spell_suggestions
                return nil
              end

              @spell_suggestions = normalized_target.merge(
                suggestions: normalized_suggestions.first(SPELL_SUGGESTION_LIMIT),
                selected_index: 0,
                scope_key: scope_key.to_s.empty? ? nil : scope_key.to_s,
                scope_label: scope_label.to_s.strip,
                can_cycle: can_cycle == true
              )
              record_cursor_activity
              nil
            end

            def spell_suggestion_state
              popup = @spell_suggestions
              return nil unless popup

              {
                word: popup[:word],
                start: popup[:start],
                end: popup[:end],
                scope_key: popup[:scope_key],
                scope_label: popup[:scope_label],
                can_cycle: popup[:can_cycle] == true,
              }
            end

            def dismiss_spell_suggestions
              @spell_suggestions = nil
              nil
            end

            private

            def spell_popup_visible?
              !@spell_suggestions.nil?
            end

            def apply_selected_spell_suggestion
              popup = @spell_suggestions
              return dismiss_spell_suggestions unless popup

              suggestion = Array(popup[:suggestions])[popup[:selected_index]]
              return dismiss_spell_suggestions if suggestion.to_s.empty?

              @note = @note[0...popup[:start]] + suggestion + @note[popup[:end]..]
              @cursor_pos = popup[:start] + suggestion.length
              dismiss_spell_suggestions
              record_cursor_activity
            end

            def move_spell_suggestion_selection(delta)
              popup = @spell_suggestions
              return unless popup

              suggestions = Array(popup[:suggestions])
              return if suggestions.empty?

              popup[:selected_index] = (popup[:selected_index].to_i + delta) % suggestions.length
              record_cursor_activity
            end

            def normalize_spell_target(target)
              return nil unless target.is_a?(Hash)

              normalized = symbolize_hash(target)
              start_index = integer_value(normalized[:start])
              end_index = integer_value(normalized[:end])
              return nil unless start_index && end_index
              return nil if end_index <= start_index

              word = @note[start_index...end_index].to_s
              return nil unless word.match?(WORD_CONTENT)

              { word: word, start: start_index, end: end_index }
            end

            def normalize_spell_suggestions(suggestions)
              Array(suggestions)
                .map { |value| value.to_s.strip }
                .reject(&:empty?)
                .each_with_object([]) do |value, normalized|
                  next if normalized.any? { |existing| existing.casecmp(value).zero? }

                  normalized << value
                end
            end

            def word_character?(char)
              return false unless char.is_a?(String)

              char.match?(WORD_CHARACTER)
            end

            def integer_value(value)
              Shoko::Shared::TypeCoercion.optional_integer(value)
            end

            def symbolize_hash(value)
              value.transform_keys do |key|
                key.is_a?(String) ? key.to_sym : key
              end
            end
          end
        end
      end
    end
  end
end
