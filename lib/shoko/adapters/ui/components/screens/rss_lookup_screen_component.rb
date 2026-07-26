# frozen_string_literal: true

require_relative '../base_component'
require_relative '../menu_design/canvas_frame'
require_relative '../menu_design/canvas_scrollbar'
require_relative '../menu_design/view_accents'
require_relative '../status_bar/palette'
require_relative '../ui/text_utils'
require 'shoko/shared/hash_normalizer'

module Shoko
  module Adapters
    module Ui
      module Components
        module Screens
          # The definition of a word looked up from an article.
          #
          # Opened from the reading pane's actions menu, in the canvas grammar
          # the rest of the menu uses: the headword on the rule, numbered
          # senses beneath it, translations after those. Dismissing returns to
          # the article with the selection still made.
          class RssLookupScreenComponent < BaseComponent
            include Ui::TextUtils

            Palette = StatusBar::Palette

            SENSE_INDENT = '   '

            def initialize(menu_state_reader: nil)
              super()
              @menu_state_reader = menu_state_reader
            end

            def preferred_height(_available_height) = :fill

            def do_render(surface, bounds)
              frame = MenuDesign::CanvasFrame.new(surface, bounds)
              frame.paint
              frame.render_rule(title: 'Dictionary', accent: accent, meta: headword)
              render_body(surface, bounds, frame)
              frame.render_hint('J/K scroll · ESC back to the article')
            end

            private

            attr_reader :menu_state_reader

            def accent = MenuDesign::ViewAccents.for(:dictionary)

            def render_body(surface, bounds, frame)
              top = frame.body_top
              height = [frame.body_bottom - top + 1, 1].max
              lines = body_lines(frame.content_width)
              return frame.write_line(top, [[status_note, Palette::LANDING_DIM_FG]]) if lines.empty?

              offset = scroll.clamp(0, [lines.length - height, 0].max)
              write_window(surface, bounds, frame, lines: lines, offset: offset, top: top, height: height)
              MenuDesign::CanvasScrollbar.render(
                surface: surface, bounds: bounds, frame: frame, top: top, height: height,
                total: lines.length, visible: height, offset: offset
              )
            end

            def write_window(surface, bounds, frame, lines:, offset:, top:, height:)
              (lines[offset, height] || []).each_with_index do |segments, index|
                surface.write(bounds, top + index, frame.content_x, frame.compose(left: segments, right: []))
              end
            end

            # Senses first, then translations, each wrapped to the measure.
            def body_lines(width)
              entries.flat_map.with_index do |entry, index|
                [
                  ([[]] if index.positive?),
                  [[entry[:word].to_s, Palette::DICT_HEADWORD_FG]],
                  numbered(entry[:senses], width),
                  translations(entry[:translations], width),
                ].compact.flatten(1)
              end
            end

            def numbered(senses, width)
              Array(senses).each_with_index.flat_map do |sense, index|
                marker = "#{index + 1}. "
                wrap_words(sense.to_s, [width - marker.length, 1].max).each_with_index.map do |line, row|
                  prefix = row.zero? ? [marker, Palette::DICT_NUM_FG] : [' ' * marker.length, nil]
                  [prefix, [line, Palette::DICT_SENSE_FG]]
                end
              end
            end

            def translations(values, width)
              text = Array(values).map(&:to_s).reject(&:empty?).join(', ')
              return [] if text.empty?

              wrap_words(text, [width - SENSE_INDENT.length, 1].max).map do |line|
                [[SENSE_INDENT, nil], [line, Palette::DICT_TRANS_FG]]
              end
            end

            def result
              Shoko::Shared::HashNormalizer.deep_symbolize(menu_state_reader&.rss_lookup_result) || {}
            end

            def entries = Array(result[:entries])

            def headword = menu_state_reader&.rss_lookup_query.to_s

            def scroll = menu_state_reader&.rss_content_scroll.to_i

            def status_note
              message = menu_state_reader&.rss_lookup_message.to_s
              return message unless message.empty?

              case menu_state_reader&.rss_lookup_status&.to_sym
              when :loading then 'Looking up…'
              when :empty then "No entry for “#{headword}”"
              else 'Nothing to show'
              end
            end
          end
        end
      end
    end
  end
end
