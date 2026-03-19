# frozen_string_literal: true

require_relative '../../base_component'

module Shoko
  module Adapters
    module Ui
      module Components
        class AnnotationEditorOverlayComponent < BaseComponent
          module RenderSupport
            # Footer rendering helpers for the annotation editor overlay.
            module FooterSupport
              private

              def render_footer(context)
                row = context[:layout].origin_y + context[:layout].height - 1
                context[:surface].write(
                  context[:bounds],
                  row,
                  context[:x],
                  pad_line(footer_hints_text, context[:width], row: row, col: context[:x])
                )
                @button_regions = footer_button_regions(context[:x], row)
              end

              def footer_hints_text
                return build_spell_footer_hints if spell_popup_visible?

                "#{glass_fg}#{DIM}Alt+D#{RESET_STYLE}#{panel_fg} spell  " \
                  "#{glass_fg}#{DIM}Ctrl+S#{RESET_STYLE}#{panel_fg} save  " \
                  "#{glass_fg}#{DIM}Esc#{RESET_STYLE}#{panel_fg} cancel"
              end

              def footer_button_regions(start_col, row)
                {
                  save: { row: row, col: start_col, width: 12 },
                  cancel: { row: row, col: start_col + 14, width: 10 },
                }
              end
            end
          end
        end
      end
    end
  end
end
