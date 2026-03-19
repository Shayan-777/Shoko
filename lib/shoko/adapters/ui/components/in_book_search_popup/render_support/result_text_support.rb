# frozen_string_literal: true

require_relative '../../base_component'

module Shoko
  module Adapters
    module Ui
      module Components
        class InBookSearchPopupComponent < BaseComponent
          module RenderSupport
            # Result-label and snippet helpers for the in-book search popup.
            module ResultTextSupport
              private

              def match_counter_text
                shown = @results.length
                total = @total_matches.to_i
                return "#{shown}/#{total} shown" if total > shown

                "#{shown} result#{plural_suffix(shown, 's')}"
              end

              def plural_suffix(count, suffix)
                count == 1 ? '' : suffix
              end

              def build_snippet_line(result)
                before = result[:before].to_s
                match = result[:match].to_s
                after = result[:after].to_s
                left = style_text(before, color: glass_fg)
                middle = style_text(match, color: panel_fg_emphasis, bold: true)
                right = style_text(after, color: glass_fg)
                " #{left}#{middle}#{right}"
              end

              def build_meta_line(result)
                chapter = result[:chapter_title].to_s.strip
                chapter = "Chapter #{result[:chapter_index].to_i + 1}" if chapter.empty?
                line_index = result[:line_index].to_i + 1
                style_text(" #{chapter} • line #{line_index}", color: glass_fg)
              end
            end
          end
        end
      end
    end
  end
end
