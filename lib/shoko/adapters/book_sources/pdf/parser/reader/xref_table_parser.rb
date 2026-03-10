# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Pdf
        module Reader
          # Parses traditional "xref ... trailer ..." sections.
          class XrefTableParser
            def initialize(data:, xref:, trailer:, dict_value:)
              @data = data
              @xref = xref
              @trailer = trailer
              @dict_value = dict_value
            end

            def parse_table(xref_offset)
              pos = skip_whitespace(xref_offset + 4)
              while pos < @data.size
                header_line, line_end = read_line(pos)
                break unless line_end

                stripped = header_line.strip
                break if stripped.start_with?('trailer')

                start_num, count = parse_subsection_header(stripped)
                break unless start_num

                pos = parse_subsection_entries(line_end + 1, start_num, count)
              end
            end

            def parse_trailer(xref_offset)
              trailer_idx = @data.index('trailer', xref_offset)
              return nil unless trailer_idx

              dict_start = @data.index('<<', trailer_idx)
              return nil unless dict_start

              dict_text = @data[dict_start...(dict_start + 500)]
              merge_trailer_values(dict_text)
              prev_value(dict_text)
            end

            private

            def skip_whitespace(pos)
              while pos < @data.size
                byte = @data.getbyte(pos)
                break unless byte && (byte.between?(0x09, 0x0D) || byte == 0x20)

                pos += 1
              end
              pos
            end

            def read_line(pos)
              line_end = @data.index("\n", pos)
              return [nil, nil] unless line_end

              [@data[pos...line_end], line_end]
            end

            def parse_subsection_header(text)
              parts = text.split
              return [nil, nil] unless parts.length == 2

              [parts[0].to_i, parts[1].to_i]
            end

            def parse_subsection_entries(pos, start_num, count)
              count.times do |idx|
                entry_line, line_end = read_line(pos)
                break unless line_end

                pos = line_end + 1
                apply_entry(start_num + idx, entry_line.to_s.strip)
              end
              pos
            end

            def apply_entry(obj_num, entry_text)
              entry_parts = entry_text.split
              return unless entry_parts.length >= 3

              entry_offset = entry_parts[0].to_i
              status = entry_parts[2]
              return unless status == 'n' && entry_offset.positive?
              return if @xref.key?(obj_num)

              @xref[obj_num] = entry_offset
            end

            def merge_trailer_values(dict_text)
              %w[Root Info Size].each do |key|
                next if @trailer.key?(key)

                value = @dict_value.call(dict_text, key)
                @trailer[key] = value if value
              end
            end

            def prev_value(dict_text)
              prev_val = @dict_value.call(dict_text, 'Prev')
              prev_val&.to_i
            end
          end
        end
      end
    end
  end
end
