# frozen_string_literal: true

require_relative '../../../shared/type_coercion'

require_relative 'base_component'
require_relative 'ui/backdrop_overlay'
require_relative 'ui/overlay_layout'
require_relative 'ui/annotation_markup'
require_relative 'ui/annotation_list_input'
require_relative 'ui/cursor_blink'
require_relative '../../../shared/terminal/text_metrics'
require_relative '../../../shared/terminal/ansi'
require_relative '../../../shared/key_definitions'
require_relative '../../../shared/terminal/text_sanitizer'
require_relative '../constants/component_palettes'

module Shoko
  module Adapters
    module Ui
      module Components
        # Overlay for creating/editing annotations.
        class AnnotationEditorOverlayComponent < BaseComponent
          require_relative 'annotation_editor_overlay/render_support'
          require_relative 'annotation_editor_overlay/spell_support'
          require_relative 'annotation_editor_overlay/input_support'

          include Adapters::Ui::Constants::Ui
          include Ui::CursorBlink
          include RenderSupport
          include SpellSupport
          include AnnotationEditorOverlayInputSupport

          SAVE_KEYS = ["\x13"].freeze # Ctrl+S
          BACKSPACE_KEYS = ["\x08", "\x7F", "\b"].freeze
          SPELL_SUGGESTION_LIMIT = 5
          SPELL_POPUP_MIN_WIDTH = 18
          SPELL_POPUP_MAX_WIDTH = 34
          SPELL_POPUP_KIND_WIDTH = 3
          WORD_CHARACTER = /\A[\p{L}\p{M}\p{N}'’-]\z/
          WORD_CONTENT = /[\p{L}\p{N}]/

          BOLD = "\e[1m"
          DIM = "\e[2m"
          ITALIC = "\e[3m"
          RESET_STYLE = "\e[22;23;24m"

          PADDING_H = 2
          PADDING_V = 1

          attr_reader :visible, :selected_text, :note, :chapter_index, :annotation_id

          def initialize(selected_text:, range:, chapter_index:, annotation: nil, color_mode: :dark,
                         rendered_lines: nil)
            super()
            normalized_annotation = symbolize_hash(annotation)
            @selected_text = (selected_text || '').dup
            @range = range
            @chapter_index = chapter_index
            @color_mode = normalize_color_mode(color_mode)
            @backdrop_overlay = Ui::BackdropOverlay.new(rendered_lines: rendered_lines)
            @annotation_id = normalized_annotation[:id]
            note_source = normalized_annotation[:note]
            @note = (note_source || '').dup
            @cursor_pos = @note.length
            @visible = true
            @button_regions = {}
            @note_inner_width = nil
            @spell_suggestions = nil
            initialize_cursor_blink
            @overlay_sizing = Ui::OverlaySizing.new(
              width_ratio: 0.55,
              width_padding: 10,
              min_width: 46,
              height_ratio: 0.50,
              height_padding: 8,
              min_height: 12
            )
          end

          def visible?
            @visible
          end

          def hide
            dismiss_spell_suggestions
            @visible = false
          end

          def update_color_mode(mode)
            @color_mode = normalize_color_mode(mode)
          end

          def update_rendered_lines(rendered_lines)
            @backdrop_overlay.update_rendered_lines(rendered_lines)
          end

          def selection_range
            @range
          end

          def render(surface, bounds)
            do_render(surface, bounds)
          end

          def do_render(surface, bounds)
            return unless @visible

            layout = overlay_layout(bounds)
            context = editor_render_context(surface, bounds, layout)
            fill_editor_background(context)
            current_row = render_header(context, context[:start_row])
            current_row = render_quote(context, current_row)
            note_end_row = layout.origin_y + layout.height - 2
            render_note_section(context, current_row, note_end_row)
            render_footer(context)
          end

          def handle_key(key)
            return handle_cancel if cancel_key?(key)
            return handle_save if save_key?(key)

            if backspace_key?(key)
              handle_backspace
            elsif ["\r", "\n"].include?(key)
              handle_enter
            elsif printable?(key)
              handle_character(key)
            end

            nil
          end

          def handle_click(col, row)
            return nil unless @visible && @button_regions

            @button_regions.each do |key, region|
              next unless row == region[:row]
              next unless col.between?(region[:col], region[:col] + region[:width] - 1)

              return handle_save if key == :save
              return { type: :cancel } if key == :cancel
            end

            nil
          end

          def calculate_width(total_width)
            @overlay_sizing.width_for(total_width)
          end

          def calculate_height(total_height)
            @overlay_sizing.height_for(total_height)
          end

          def handle_backspace
            dismiss_spell_suggestions
            return if @cursor_pos.zero?

            @note = @note[0...(@cursor_pos - 1)] + @note[@cursor_pos..]
            @cursor_pos -= 1
            record_cursor_activity
          end

          def handle_enter
            if spell_popup_visible?
              apply_selected_spell_suggestion
              return nil
            end

            @note, @cursor_pos = Ui::AnnotationListInput.insert_newline(@note, @cursor_pos)
            record_cursor_activity
          end

          def handle_character(char)
            return unless printable?(char)

            dismiss_spell_suggestions
            @note, @cursor_pos = Ui::AnnotationListInput.insert_character(@note, @cursor_pos, char)
            record_cursor_activity
          end

          def handle_move_left
            dismiss_spell_suggestions
            move_cursor { |styler, cursor, width| styler.move_left(cursor, width) }
          end

          def handle_move_right
            dismiss_spell_suggestions
            move_cursor { |styler, cursor, width| styler.move_right(cursor, width) }
          end

          def handle_move_up
            if spell_popup_visible?
              move_spell_suggestion_selection(-1)
              return nil
            end

            move_cursor { |styler, cursor, width| styler.move_up(cursor, width) }
          end

          def handle_move_down
            if spell_popup_visible?
              move_spell_suggestion_selection(1)
              return nil
            end

            move_cursor { |styler, cursor, width| styler.move_down(cursor, width) }
          end

          def handle_save
            { type: :save, note: @note }
          end

          def handle_cancel
            return dismiss_spell_suggestions if spell_popup_visible?

            { type: :cancel }
          end

          def save_annotation
            handle_save
          end

          def cancel_annotation
            handle_cancel
          end
        end
      end
    end
  end
end
