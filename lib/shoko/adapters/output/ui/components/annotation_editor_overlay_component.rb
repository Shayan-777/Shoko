# frozen_string_literal: true

require_relative 'base_component'
require_relative 'render_style'
require_relative 'ui/overlay_layout'
require_relative 'annotation_editor_overlay/footer_renderer'
require_relative 'annotation_editor_overlay/geometry'
require_relative 'annotation_editor_overlay/note_renderer'
require_relative '../../terminal/text_metrics'
require_relative '../../../input/key_definitions'
require_relative '../../terminal/terminal_sanitizer'

module Shoko
  module Adapters::Output::Ui::Components
    # Overlay for creating/editing annotations without leaving the reader view.
    class AnnotationEditorOverlayComponent < BaseComponent
      include Adapters::Output::Ui::Constants::UI

      SAVE_KEYS = ["\x13"].freeze # Ctrl+S
      BACKSPACE_KEYS = ["\x08", "\x7F", '\b'].freeze

      attr_reader :visible, :selected_text, :note, :chapter_index, :annotation_id

      def initialize(selected_text:, range:, chapter_index:, annotation: nil)
        super()
        @selected_text = (selected_text || '').dup
        @range = range
        @chapter_index = chapter_index
        @annotation_id = annotation.is_a?(Hash) ? (annotation[:id] || annotation['id']) : nil
        note_source = annotation.is_a?(Hash) ? (annotation[:note] || annotation['note']) : nil
        @note = (note_source || '').dup
        @cursor_pos = @note.length
        @visible = true
        @button_regions = {}
        @overlay_sizing = UI::OverlaySizing.new(
          width_ratio: 0.7,
          width_padding: 10,
          min_width: 60,
          height_ratio: 0.6,
          height_padding: 6,
          min_height: 16
        )
      end

      def visible?
        @visible
      end

      def hide
        @visible = false
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

        render_panel(surface, bounds, layout)

        geometry = AnnotationEditorOverlay::Geometry.new(layout)
        render_header(surface, bounds, geometry)
        render_selection_summary(surface, bounds, geometry)
        render_field_label(surface, bounds, geometry)
        note_renderer = AnnotationEditorOverlay::NoteRenderer.new(
          background: ANNOTATION_PANEL_BG,
          text_color: theme_primary,
          cursor_color: theme_accent,
          geometry: geometry,
          placeholder_text: 'Write your annotation...',
          placeholder_color: COLOR_TEXT_DIM
        )
        note_renderer.render(surface, bounds, note: @note, cursor_pos: @cursor_pos)

        footer_renderer = AnnotationEditorOverlay::FooterRenderer.new(
          background: ANNOTATION_PANEL_BG,
          text_fg: theme_primary,
          key_fg: COLOR_TEXT_DIM
        )
        @button_regions = footer_renderer.render(surface, bounds, geometry)
      end

      # Handles key input, returning an event hash when an action should be taken.
      def handle_key(key)
        return { type: :cancel } if cancel_key?(key)
        return handle_save if save_key?(key)

        case key
        when *BACKSPACE_KEYS
          handle_backspace
        when "\r", "\n"
          insert_newline
        else
          insert_character(key)
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
        return if @cursor_pos.zero?

        @note.slice!(@cursor_pos - 1)
        @cursor_pos -= 1
      end

      def handle_enter
        insert_newline
      end

      def handle_character(key)
        insert_character(key)
      end

      def insert_newline
        insert_text("\n")
      end

      def insert_character(key)
        return unless printable?(key)

        insert_text(key)
      end

      def insert_text(str)
        @note.insert(@cursor_pos, str)
        @cursor_pos += str.length
      end

      def printable?(key)
        Shoko::Adapters::Output::Terminal::TerminalSanitizer.printable_char?(key.to_s)
      end

      def save_key?(key)
        SAVE_KEYS.include?(key)
      end

      def cancel_key?(key)
        Adapters::Input::KeyDefinitions::ACTIONS[:cancel].include?(key)
      end

      def handle_save
        { type: :save, note: @note }
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

      private

      def render_panel(surface, bounds, layout)
        layout.fill_background(surface, bounds, background: ANNOTATION_PANEL_BG)
      end

      def render_header(surface, bounds, geometry)
        reset = Terminal::ANSI::RESET
        title = 'Annotation'
        surface.write(bounds, geometry.header_row, geometry.content_x,
                      "#{ANNOTATION_PANEL_BG}#{ANNOTATION_HEADER_FG}#{title}#{reset}")
      end

      def render_selection_summary(surface, bounds, geometry)
        reset = Terminal::ANSI::RESET
        summary = selection_summary_text(geometry)
        return if summary.empty?

        surface.write(bounds, geometry.subheader_row, geometry.content_x,
                      "#{ANNOTATION_PANEL_BG}#{summary}#{reset}")
      end

      def render_field_label(surface, bounds, geometry)
        label = 'Note'
        surface.write(bounds, geometry.label_row, geometry.content_x,
                      "#{ANNOTATION_PANEL_BG}#{COLOR_TEXT_DIM}#{label}#{Terminal::ANSI::RESET}")
      end

      def selection_summary_text(geometry)
        sanitized = Shoko::Adapters::Output::Terminal::TerminalSanitizer.sanitize(@selected_text.to_s,
                                                                                  preserve_newlines: false,
                                                                                  preserve_tabs: false)
        condensed = sanitized.gsub(/\s+/, ' ').strip
        return "#{COLOR_TEXT_DIM}Write your note below" if condensed.empty?

        label = 'Selected: '
        max = geometry.content_width - Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(label)
        snippet = Shoko::Adapters::Output::Terminal::TextMetrics.truncate_to(condensed, [max, 1].max)
        "#{COLOR_TEXT_DIM}#{label}#{theme_primary}#{snippet}"
      end

      def theme_accent
        Shoko::Adapters::Output::Ui::Components::RenderStyle.color(:accent)
      rescue StandardError
        COLOR_TEXT_ACCENT
      end

      def theme_primary
        Shoko::Adapters::Output::Ui::Components::RenderStyle.color(:primary)
      rescue StandardError
        COLOR_TEXT_PRIMARY
      end

      def overlay_layout(bounds)
        width = calculate_width(bounds.width)
        height = calculate_height(bounds.height)
        UI::OverlayLayout.centered(bounds, width: width, height: height)
      end
    end
  end
end
