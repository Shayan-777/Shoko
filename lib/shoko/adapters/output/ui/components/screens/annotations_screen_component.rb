# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../../terminal/terminal_sanitizer'
require_relative '../ui/text_utils'
require_relative '../ui/list_helpers'
require_relative 'annotation_rendering_helpers'

module Shoko
  module Adapters::Output::Ui::Components
    module Screens
      # Annotations screen component for viewing and managing annotations
      class AnnotationsScreenComponent < BaseComponent
        include Adapters::Output::Ui::Constants::Ui
        include Ui::TextUtils
        include AnnotationsListRendering

        def initialize(dependencies: nil)
          super()
          @dependencies = dependencies
          @reader_state_reader = nil
          @menu_state_reader = nil
          @selected = 0
          @list = []
          @mode = :book
          @current_book_path = nil
          @current_annotation = nil
          refresh_data
        end

        attr_reader :selected, :current_annotation, :current_book_path

        def selected=(value)
          @selected = [value, 0].max
          update_current_annotation
        end

        def navigate(direction)
          annotations = current_annotations
          return if annotations.empty?

          case direction
          when :up then @selected = [@selected - 1, 0].max
          when :down then @selected = [@selected + 1, annotations.length - 1].min
          end

          update_current_annotation
        end

        def refresh_data
          prev_selected = @selected
          load_annotations_for_mode
          clamp_selection(prev_selected)
          update_current_annotation
        end

        def do_render(surface, bounds)
          refresh_data
          all_mode = (@mode == :all)
          annotations = current_annotations
          ctx = build_list_context(surface, bounds, all_mode)

          render_list_header(ctx, annotations.length, build_book_label(all_mode))
          render_list_column_headers(ctx)

          if annotations.empty?
            render_empty_state(ctx)
          else
            render_visible_annotations(ctx, annotations)
          end

          render_list_footer(ctx)
        end

        def preferred_height(_available_height)
          :fill
        end

        private

        def current_annotations
          @list || []
        end

        def load_annotations_for_mode
          path = reader_state_reader&.book_path
          if path && !path.to_s.empty?
            load_book_annotations(path)
          else
            load_all_annotations
          end
        end

        def load_book_annotations(path)
          @mode = :book
          @current_book_path = path
          raw = reader_state_reader&.annotations || []
          @list = normalize_list(raw).map { |a| a.merge(book_path: path) }
        end

        def load_all_annotations
          @mode = :all
          mapping = menu_state_reader&.annotations_all || {}
          @list = mapping.flat_map do |book_path, items|
            normalize_list(items).map { |a| a.merge(book_path: book_path) }
          end
        end

        def reader_state_reader
          return @reader_state_reader if @reader_state_reader

          @reader_state_reader = @dependencies&.reader_state_reader
        end

        def menu_state_reader
          return @menu_state_reader if @menu_state_reader

          @menu_state_reader = @dependencies&.menu_state_reader
        end

        def clamp_selection(prev_selected)
          upper = [current_annotations.length - 1, 0].max
          @selected = prev_selected.clamp(0, upper)
        end

        def update_current_annotation
          annotations = current_annotations
          @current_annotation = annotations[@selected] if @selected < annotations.length
          return unless @current_annotation

          book_path = @current_annotation[:book_path]
          @current_book_path = book_path if book_path
        end

        def build_book_label(all_mode)
          if @current_book_path
            sanitize_filename(File.basename(@current_book_path))
          else
            all_mode ? 'All Books' : 'No book selected'
          end
        end

        def render_empty_state(ctx)
          mid = ctx.height / 2
          write_centered_dim(ctx, mid, 'No annotations found')
          write_centered_dim(ctx, mid + 2, 'Annotations you create while reading will appear here')
        end

        def write_centered_dim(ctx, row, text)
          styled = "#{COLOR_TEXT_DIM}#{text}#{Terminal::ANSI::RESET}"
          visible_len = Shoko::Adapters::Output::Terminal::TextMetrics.visible_length(text)
          col = [(ctx.width - visible_len + 10) / 2, 1].max
          ctx.surface.write(ctx.bounds, row, col, styled)
        end

        def render_list_footer(ctx)
          footer = "#{COLOR_TEXT_DIM}[up/dn] Navigate [Enter] Open [d] Delete [ESC] Back#{Terminal::ANSI::RESET}"
          ctx.surface.write(ctx.bounds, ctx.height - 2, 2, footer)
        end

        def render_visible_annotations(ctx, annotations)
          list_start_row = 4
          list_height = ctx.height - list_start_row - 2
          return if list_height <= 0

          start_index, visible = Ui::ListHelpers.slice_visible(annotations, list_height, @selected)

          visible.each_with_index do |annotation, index|
            row = list_start_row + index
            abs_idx = start_index + index
            row_data = RowData.new(annotation: annotation, abs_idx: abs_idx, selected_idx: @selected)
            render_annotation_row(ctx, row, row_data)
          end
        end

        def normalize_list(raw)
          (raw || []).map do |a|
            {
              text: a['text'],
              note: a['note'],
              id: a['id'],
              range: a['range'],
              chapter_index: a['chapter_index'],
              created_at: a['created_at'],
              updated_at: a['updated_at'],
              page_current: a['page_current'],
              page_total: a['page_total'],
              page_mode: a['page_mode'],
            }
          end
        end
      end
    end
  end
end
