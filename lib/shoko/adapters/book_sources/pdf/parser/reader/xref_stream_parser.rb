# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Pdf
        module Reader
          # Parses cross-reference streams (PDF 1.5+).
          class XrefStreamParser
            def initialize(data:, xref:, compressed:, trailer:, dict_value:, read_stream_bytes:, decompress:,
                           predictor:, import_budget:)
              @data = data
              @xref = xref
              @compressed = compressed
              @trailer = trailer
              @dict_value = dict_value
              @read_stream_bytes = read_stream_bytes
              @decompress = decompress
              @predictor = predictor
              @import_budget = import_budget
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
              parse_options = { entry_size: entry_size, type_width: w1, offset_width: w2, index_width: w3 }
              indices.each_slice(2) do |start_num, count|
                break unless count

                @import_budget.consume_structure!(count, label: 'PDF xref stream')
                section_options = parse_options.merge(start_num: start_num, count: count)
                offset = parse_subsection_entries(stream_data, offset, section_options)
              end
            end

            private

            def parse_subsection_entries(stream_data, offset, options)
              options[:count].times do |position|
                break if offset + options[:entry_size] > stream_data.length

                entry_type, field2, field3 = read_entry_fields(stream_data, offset, options)
                apply_entry(options[:start_num] + position, entry_type, field2, field3)
                offset += options[:entry_size]
              end
              offset
            end

            # Each entry is W[0]+W[1]+W[2] bytes: type, field2 (offset or stream
            # number), field3 (generation or index). A zero type width defaults
            # the type to 1 per the spec.
            def read_entry_fields(stream_data, offset, options)
              type_width = options[:type_width]
              offset_width = options[:offset_width]
              entry_type = type_width.zero? ? 1 : read_uint(stream_data, offset, type_width)
              field2 = read_uint(stream_data, offset + type_width, offset_width)
              field3 = read_uint(stream_data, offset + type_width + offset_width, options[:index_width])
              [entry_type, field2, field3]
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
              data_start = StreamOffset.data_start(@data, stream_start)
              raw = @read_stream_bytes.call(data_start, header)
              return nil unless raw

              decoded = header.include?('FlateDecode') ? @decompress.call(raw) : raw
              @predictor.apply(decoded, header)
            end

            def read_uint(data, offset, width)
              return 0 if width.zero?

              value = 0
              width.times do |idx|
                value = (value << 8) | (data.getbyte(offset + idx) || 0)
              end
              value
            end

            # Type 1: object at a direct byte offset (field2). Type 2: object
            # inside a compressed object stream (field2 = stream object number,
            # field3 = index within it). First occurrence wins, so an older xref
            # section reached via /Prev never overwrites a newer one.
            def apply_entry(obj_num, entry_type, field2, field3)
              return if @xref.key?(obj_num) || @compressed.key?(obj_num)

              case entry_type
              when 1 then @xref[obj_num] = field2 if field2.positive?
              when 2 then @compressed[obj_num] = [field2, field3] if field2.positive?
              end
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
