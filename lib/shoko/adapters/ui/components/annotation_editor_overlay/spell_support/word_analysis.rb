# frozen_string_literal: true

require_relative '../../base_component'

module Shoko
  module Adapters
    module Ui
      module Components
        class AnnotationEditorOverlayComponent < BaseComponent
          module SpellSupport
            # Word-boundary analysis for spellcheck targets and cursor context.
            module WordAnalysis
              def spellcheck_target
                range = current_word_range
                return nil unless range

                {
                  word: @note[range[:start]...range[:end]].to_s,
                  start: range[:start],
                  end: range[:end],
                }
              end

              private

              def current_word_range
                text = @note.to_s
                return nil if text.empty?

                anchor = word_anchor(text)
                return nil unless anchor

                start_index = word_start_index(text, anchor)
                end_index = word_end_index(text, anchor)
                valid_word_range(text, start_index, end_index)
              end

              def word_anchor(text)
                cursor = @cursor_pos.to_i.clamp(0, text.length)
                return cursor - 1 if cursor.positive? && word_character?(text[cursor - 1])
                return cursor if word_character?(text[cursor])

                nil
              end

              def word_start_index(text, anchor)
                start_index = anchor
                start_index -= 1 while start_index.positive? && word_character?(text[start_index - 1])
                start_index
              end

              def word_end_index(text, anchor)
                end_index = anchor + 1
                end_index += 1 while end_index < text.length && word_character?(text[end_index])
                end_index
              end

              def valid_word_range(text, start_index, end_index)
                word = text[start_index...end_index].to_s
                return nil unless word.match?(WORD_CONTENT)

                { start: start_index, end: end_index }
              end
            end
          end
        end
      end
    end
  end
end
