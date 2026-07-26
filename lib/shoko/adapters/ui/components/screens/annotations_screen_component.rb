# frozen_string_literal: true

require 'uri'

require_relative '../base_component'
require 'shoko/shared/hash_normalizer'
require 'shoko/shared/terminal/text_sanitizer'
require_relative '../menu_design/canvas_frame'
require_relative '../menu_design/canvas_list'
require_relative '../menu_design/view_accents'
require_relative '../status_bar/palette'
require_relative '../ui/text_utils'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # Annotations — every saved note across the shelf (or the open
          # book's notes), rendered as the menu-side sibling of the in-book
          # notes panel: two-row blocks with the note (or its excerpt) leading
          # and the excerpt · book · chapter · date line beneath, carrying the
          # family's selection strip and a slim scrollbar when the list
          # overflows. ENTER drills into the detail view.
          class AnnotationsScreenComponent < BaseComponent
            TextSanitizer = Shoko::Shared::Terminal::TextSanitizer

            include Ui::TextUtils

            Palette = StatusBar::Palette

            ROWS_PER_NOTE = 2

            def initialize(menu_state_reader: nil, reader_state_reader: nil, menu_hit_registry: nil,
                           menu_visual_profile: nil)
              super()
              @menu_state_reader = menu_state_reader
              @reader_state_reader = reader_state_reader
              @menu_hit_registry = menu_hit_registry
              @menu_visual_profile = menu_visual_profile
              @mode = :all
              @list = []
              @selected = 0
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
              annotations = current_annotations
              frame = MenuDesign::CanvasFrame.new(surface, bounds)
              frame.paint
              frame.render_rule(title: 'Annotations', accent: accent, meta: rule_meta(annotations))
              if annotations.empty?
                render_empty(frame)
              else
                render_blocks(surface, bounds, frame, annotations)
              end
              frame.render_hint(hint_text(annotations))
            end

            def preferred_height(_available_height)
              :fill
            end

            private

            def accent
              MenuDesign::ViewAccents.for(:annotations)
            end

            def hits
              @menu_hit_registry
            end

            def rule_meta(annotations)
              count = "#{annotations.length} #{annotations.length == 1 ? 'note' : 'notes'}"
              "#{count} · #{annotation_scope_label}"
            end

            def annotation_scope_label
              @mode == :book ? compact_book_label(@current_book_path) : 'everything'
            end

            def hint_text(annotations)
              return 'Add notes while reading — press a on a selection' if annotations.empty?

              'ENTER open · E edit · D delete · wheel scrolls · ESC back'
            end

            def render_empty(frame)
              row = frame.body_top + [frame.body_height / 2, 0].max - 1
              frame.write_line(row, [['No annotations yet.', Palette::LANDING_DIM_FG]])
              frame.write_line(row + 2, [['Select a passage in a book and press a to keep', Palette::LANDING_DIM_FG]])
              frame.write_line(row + 3, [['a note anchored to it.', Palette::LANDING_DIM_FG]])
            end

            def render_blocks(surface, bounds, frame, annotations)
              top = frame.body_top
              height = frame.body_height
              return if height <= 0

              list = MenuDesign::CanvasList.new(surface, bounds, frame: frame, hits: hits)
              list.register_wheel(top: top, height: height, action: { type: :list_wheel, list: :annotations })
              window = visible_window(annotations, height)
              render_note_blocks(list, window, top)
              list.render_scrollbar(top: top, height: height, total: annotations.length,
                                    visible: window[:capacity], offset: window[:start])
            end

            def render_note_blocks(list, window, top)
              window[:items].each_with_index do |annotation, offset|
                index = window[:start] + offset
                list.block(
                  row: top + (offset * ROWS_PER_NOTE),
                  lines: block_rows(annotation, index == @selected),
                  selected: index == @selected,
                  action: { type: :list_row, list: :annotations, index: index }
                )
              end
            end

            def block_rows(annotation, selected)
              primary_fg = selected ? Palette::LANDING_TITLE_FG : Palette::LANDING_TEXT_FG
              [
                { left: [[primary_line(annotation), primary_fg]] },
                { left: [[secondary_line(annotation), Palette::LANDING_DIM_FG]],
                  right: [[created_at_label(annotation[:created_at]), Palette::LANDING_DIM_FG]] },
              ]
            end

            # The note leads; a note-less annotation leads with its excerpt.
            def primary_line(annotation)
              note = one_line(annotation[:note])
              return note unless note.empty?

              excerpt = one_line(annotation[:text])
              excerpt.empty? ? '(empty note)' : excerpt
            end

            def secondary_line(annotation)
              parts = []
              excerpt = one_line(annotation[:text])
              parts << "❝ #{excerpt} ❞" if !excerpt.empty? && !one_line(annotation[:note]).empty?
              parts << compact_book_label(annotation[:book_path]) if @mode == :all
              parts << "Ch #{annotation[:chapter_index]}" if annotation[:chapter_index]
              parts.join(' · ')
            end

            def visible_window(annotations, height)
              capacity = [height / ROWS_PER_NOTE, 1].max
              start = if annotations.length <= capacity
                        0
                      else
                        (@selected - (capacity / 2)).clamp(0, annotations.length - capacity)
                      end
              { start: start, items: annotations[start, capacity] || [], capacity: capacity }
            end

            # ----- data -----

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

            def normalize_list(raw)
              (raw || []).map do |a|
                annotation = Shoko::Shared::HashNormalizer.deep_symbolize(a) || {}
                {
                  text: annotation[:text],
                  note: annotation[:note],
                  id: annotation[:id],
                  anchor: annotation[:anchor],
                  chapter_index: annotation[:chapter_index],
                  created_at: annotation[:created_at],
                  updated_at: annotation[:updated_at],
                }
              end
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

            def created_at_label(value)
              saved = value.to_s.split('T', 2).first.to_s
              saved.empty? ? '—' : saved
            end

            # Notes are keyed by whatever they were made on: a book by its
            # file path, an article by its URL. A URL has no useful basename
            # (it is usually the slug or an id), so it is shown as its host
            # and last readable segment instead of a bare filename.
            def compact_book_label(path)
              text = path.to_s
              return article_label(text) if text.match?(%r{\Ahttps?://})

              base = File.basename(text, '.*')
              base.empty? ? 'book' : TextSanitizer.single_line(base)
            end

            def article_label(url)
              uri = URI.parse(url)
              host = uri.host.to_s.delete_prefix('www.')
              slug = uri.path.to_s.split('/').reject(&:empty?).reverse
                        .find { |part| part.match?(/[a-z]{4}/i) }
              TextSanitizer.single_line([host, humanized_slug(slug)].compact.reject(&:empty?).join(' · '))
            rescue URI::InvalidURIError
              TextSanitizer.single_line(url)
            end

            def humanized_slug(slug)
              return '' unless slug

              slug.tr('-_', '  ').squeeze(' ').strip
            end

            def one_line(text, fallback: '')
              clean = TextSanitizer.single_line(text.to_s).strip
              clean.empty? ? fallback : clean
            end

            attr_reader :reader_state_reader, :menu_state_reader
          end
        end
      end
    end
  end
end
