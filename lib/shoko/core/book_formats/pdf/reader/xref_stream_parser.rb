# frozen_string_literal: true

module Shoko
  module Core
    module BookFormats
      module Pdf
        module Reader
          # Parses cross-reference streams (PDF 1.5+).
          class XrefStreamParser
            def initialize(data:, xref:, trailer:, dict_value:, read_stream_bytes:, decompress:)
              @data = data
              @xref = xref
              @trailer = trailer
              @dict_value = dict_value
              @read_stream_bytes = read_stream_bytes
              @decompress = decompress
            end

            def parse(offset)
              stream_start = @data.index('stream', offset)
              return nil unless stream_start

              header = @data[offset...stream_start]
              merge_trailer_values(header)

              widths = parse_widths(header)
              return nil unless widths

              stream_data = read_stream_data(stream_start, header)
              return nil unless stream_data

              parse_entries(stream_data, widths, parse_indices(header))
              prev_value(header)
            end

            def parse_entries(stream_data, widths, indices)
              stream_data.force_encoding(Encoding::BINARY)
              w1, w2, w3 = widths
              entry_size = w1 + w2 + w3
              return if entry_size.zero?

              offset = 0
              parse_options = { entry_size: entry_size, type_width: w1, offset_width: w2 }
              indices.each_slice(2) do |start_num, count|
                break unless count

                section_options = parse_options.merge(start_num: start_num, count: count)
                offset = parse_subsection_entries(stream_data, offset, section_options)
              end
            end

            private

            def parse_subsection_entries(stream_data, offset, options)
              options[:count].times do |position|
                break if offset + options[:entry_size] > stream_data.length

                entry_type = read_uint(stream_data, offset, options[:type_width])
                entry_type = 1 if options[:type_width].zero?
                entry_offset = read_uint(stream_data, offset + options[:type_width], options[:offset_width])
                offset += options[:entry_size]

                apply_entry(options[:start_num] + position, entry_type, entry_offset)
              end
              offset
            end

            def merge_trailer_values(header)
              %w[Root Info Size].each do |key|
                next if @trailer.key?(key)

                value = @dict_value.call(header, key)
                @trailer[key] = value if value
              end
            end

            def parse_widths(header)
              w_text = @dict_value.call(header, 'W')
              return nil unless w_text

              widths = w_text.scan(/\d+/).map(&:to_i)
              widths.length == 3 ? widths : nil
            end

            def parse_indices(header)
              index_text = @dict_value.call(header, 'Index')
              return index_text.scan(/\d+/).map(&:to_i) if index_text

              size = @dict_value.call(header, 'Size').to_i
              [0, size]
            end

            def read_stream_data(stream_start, header)
              data_start = stream_data_start(stream_start)
              raw = @read_stream_bytes.call(data_start, header)
              return nil unless raw

              header.include?('FlateDecode') ? @decompress.call(raw) : raw
            end

            def stream_data_start(stream_start)
              pos = stream_start + 6
              pos += 1 if @data.getbyte(pos) == 0x0D
              pos += 1 if @data.getbyte(pos) == 0x0A
              pos
            end

            def read_uint(data, offset, width)
              return 0 if width.zero?

              value = 0
              width.times do |idx|
                value = (value << 8) | (data.getbyte(offset + idx) || 0)
              end
              value
            end

            def apply_entry(obj_num, entry_type, entry_offset)
              return unless entry_type == 1
              return unless entry_offset.positive?
              return if @xref.key?(obj_num)

              @xref[obj_num] = entry_offset
            end

            def prev_value(header)
              prev_val = @dict_value.call(header, 'Prev')
              prev_val&.to_i
            end
          end
        end
      end
    end
  end
end
