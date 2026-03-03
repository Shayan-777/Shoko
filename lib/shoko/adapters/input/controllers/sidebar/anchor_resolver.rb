# frozen_string_literal: true

require 'cgi'
require_relative '../../../../core/models/content_block'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Sidebar
          # Resolves TOC href anchors into chapter line offsets.
          class AnchorResolver
            def initialize(document_reader:, formatting_service:, layout_service:, ui_state_reader:, config_reader:,
                           sidebar_state_reader:)
              @document_reader = document_reader
              @formatting_service = formatting_service
              @layout_service = layout_service
              @ui_state_reader = ui_state_reader
              @config_reader = config_reader
              @sidebar_state_reader = sidebar_state_reader
            end

            def line_offset_for_toc_entry(entry, chapter_index)
              anchor = anchor_from_href(entry&.href)
              return nil if anchor.nil? || anchor.empty?

              lines = wrapped_lines_for_anchor(chapter_index)
              return nil if lines.nil? || lines.empty?

              anchor_down = anchor.downcase
              lines.each_with_index do |line, idx|
                next unless line.is_a?(Shoko::Core::Models::DisplayLine)

                anchors = line.metadata[:anchors] || line.metadata['anchors']
                next unless anchors

                anchors = Array(anchors).map(&:to_s)
                return idx if anchors.include?(anchor)
                return idx if anchors.any? { |value| value.casecmp?(anchor) }
                return idx if anchors.any? { |value| value.downcase == anchor_down }
              end
              nil
            rescue Shoko::Error
              nil
            end

            def anchor_from_href(href)
              return nil if href.nil?

              fragment = href.to_s.split('#', 2)[1]
              return nil if fragment.nil? || fragment.empty?

              CGI.unescape(fragment.to_s).strip
            rescue Shoko::Error
              nil
            end

            private

            def wrapped_lines_for_anchor(chapter_index)
              return nil unless @formatting_service && @layout_service && document

              width = (@ui_state_reader.terminal_width || 80).to_i
              height = (@ui_state_reader.terminal_height || 24).to_i
              view_mode = @config_reader.view_mode
              line_spacing = @config_reader.line_spacing
              effective_width = @layout_service.effective_content_width(
                width,
                sidebar_visible: @sidebar_state_reader.sidebar_visible?
              )
              col_width, content_height = @layout_service.calculate_metrics(effective_width, height, view_mode)
              lines_per_page = @layout_service.adjust_for_line_spacing(content_height, line_spacing)

              @formatting_service.wrap_all(document, chapter_index, col_width,
                                           config: @config_reader, lines_per_page: lines_per_page)
            rescue Shoko::Error
              nil
            end

            def document
              @document_reader.call
            end
          end
        end
      end
    end
  end
end
