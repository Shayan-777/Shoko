# frozen_string_literal: true

require 'set'
require 'zlib'

module Shoko
  module Core
    module BookFormats
      module Pdf
        # Low-level PDF file reader. Parses the cross-reference table, reads
        # individual objects by number, decompresses FlateDecode streams, and
        # provides helpers for navigating the object graph.
        #
        # Only depends on Ruby stdlib (zlib for decompression).
        class PdfReader
          attr_reader :data, :xref, :trailer

          # @param data [String] binary PDF payload
          def initialize(data)
            @data = data.to_s.dup
            @data.force_encoding(Encoding::BINARY)
            @xref = {}
            @trailer = {}
            @object_cache = {}
            parse_structure
          end

          # Read the raw dictionary text for an object.
          # @param obj_num [Integer]
          # @return [String, nil]
          def read_object_raw(obj_num)
            return @object_cache[obj_num] if @object_cache.key?(obj_num)

            offset = @xref[obj_num.to_i]
            return nil unless offset

            endobj_idx = @data.index('endobj', offset)
            return nil unless endobj_idx

            raw = @data[offset..endobj_idx + 5]
            @object_cache[obj_num] = raw
            raw
          end

          # Read and decompress a stream object.
          # @param obj_num [Integer]
          # @return [String, nil] decompressed stream content
          def read_stream(obj_num)
            offset = @xref[obj_num.to_i]
            return nil unless offset

            stream_start_marker = @data.index('stream', offset)
            return nil unless stream_start_marker

            endobj_idx = @data.index('endobj', offset)
            return nil unless endobj_idx && stream_start_marker < endobj_idx

            header = @data[offset...stream_start_marker]

            pos = stream_start_marker + 6 # length of 'stream'
            pos += 1 if @data.getbyte(pos) == 0x0D # \r
            pos += 1 if @data.getbyte(pos) == 0x0A # \n

            raw = read_stream_bytes(pos, header)
            return nil unless raw

            if header.include?('FlateDecode')
              decompress(raw)
            else
              raw
            end
          end

          # Resolve an indirect object reference like "68 0 R" to the object number.
          # @param ref_string [String] e.g. "68 0 R"
          # @return [Integer, nil]
          def resolve_ref(ref_string)
            match = ref_string.to_s.match(/(\d+)\s+\d+\s+R/)
            match ? match[1].to_i : nil
          end

          # Extract a simple value for a key from a PDF dictionary string.
          # Handles: /Key(string), /Key N G R, /Key/Name, /Key N (integer)
          # @param dict_text [String]
          # @param key [String] without leading /
          # @return [String, nil]
          def dict_value(dict_text, key)
            return nil unless dict_text

            # Match /Key followed by value
            pattern = /\/#{Regexp.escape(key)}\s*/
            match = dict_text.match(pattern)
            return nil unless match

            rest = dict_text[match.end(0)..]
            return nil unless rest

            case rest[0]
            when '('
              extract_parenthesized(rest)
            when '<'
              if rest[1] == '<'
                extract_nested_dict(rest)
              else
                extract_hex_string(rest)
              end
            when '['
              extract_array(rest)
            when '/'
              # Name value
              rest.match(/\A\/([^\s\/<>\[\]()]+)/)&.[](1)
            else
              # Number or reference: "68 0 R" or "345"
              ref_match = rest.match(/\A(\d+)\s+(\d+)\s+R/)
              if ref_match
                "#{ref_match[1]} #{ref_match[2]} R"
              else
                num_match = rest.match(/\A-?[\d.]+/)
                num_match&.[](0)
              end
            end
          end

          # Get the root catalog object number.
          # @return [Integer, nil]
          def root_obj_num
            resolve_ref(@trailer['Root'])
          end

          # Get the info dictionary object number.
          # @return [Integer, nil]
          def info_obj_num
            resolve_ref(@trailer['Info'])
          end

          # Collect all page object numbers in document order.
          # @return [Array<Integer>]
          def page_object_numbers
            root = read_object_raw(root_obj_num)
            return [] unless root

            pages_ref = dict_value(root, 'Pages')
            pages_num = resolve_ref(pages_ref)
            return [] unless pages_num

            collect_pages(pages_num)
          end

          private

          def parse_structure
            startxref_idx = @data.rindex('startxref')
            return unless startxref_idx

            xref_offset = @data[startxref_idx + 9..startxref_idx + 30].strip.to_i
            parse_xref_chain(xref_offset)
          end

          # Follow the chain of xref sections (via /Prev) to build the complete table.
          # Earlier entries are overwritten by later ones (most recent wins).
          def parse_xref_chain(offset)
            visited = Set.new
            current_offset = offset

            while current_offset && current_offset > 0 && !visited.include?(current_offset)
              visited << current_offset
              prev_offset = nil

              if @data[current_offset, 4] == 'xref'
                parse_traditional_xref(current_offset)
                prev_offset = parse_trailer_dict_at(current_offset)
              else
                prev_offset = parse_xref_stream(current_offset)
              end

              current_offset = prev_offset
            end
          end

          # Parse a traditional xref table starting at the given offset.
          def parse_traditional_xref(xref_offset)
            pos = xref_offset + 4
            pos += 1 while pos < @data.size && (@data.getbyte(pos)&.between?(0x09, 0x0D) || @data.getbyte(pos) == 0x20)

            while pos < @data.size
              line_end = @data.index("\n", pos) || break
              header_line = @data[pos...line_end].strip
              break if header_line.start_with?('trailer')

              parts = header_line.split
              break unless parts.length == 2

              start_num = parts[0].to_i
              count = parts[1].to_i
              pos = line_end + 1

              count.times do |i|
                entry_end = @data.index("\n", pos) || break
                entry = @data[pos...entry_end].strip
                pos = entry_end + 1

                entry_parts = entry.split
                next unless entry_parts.length >= 3

                entry_offset = entry_parts[0].to_i
                status = entry_parts[2]
                obj_num = start_num + i
                @xref[obj_num] = entry_offset if status == 'n' && entry_offset > 0 && !@xref.key?(obj_num)
              end
            end
          end

          # Parse the trailer dictionary following a traditional xref table.
          # Populates @trailer and returns the /Prev offset (or nil).
          def parse_trailer_dict_at(xref_offset)
            trailer_idx = @data.index('trailer', xref_offset)
            return nil unless trailer_idx

            dict_start = @data.index('<<', trailer_idx)
            return nil unless dict_start

            dict_text = @data[dict_start..dict_start + 500]

            %w[Root Info Size].each do |key|
              next if @trailer.key?(key)

              value = dict_value(dict_text, key)
              @trailer[key] = value if value
            end

            prev_val = dict_value(dict_text, 'Prev')
            prev_val ? prev_val.to_i : nil
          end

          # Parse a cross-reference stream object (PDF 1.5+).
          # The xref data is stored in a compressed stream instead of a text table.
          # Returns the /Prev offset (or nil).
          def parse_xref_stream(offset)
            # Read the stream object header to get /W, /Size, /Index, /Root, /Info, /Prev
            stream_start = @data.index('stream', offset)
            return nil unless stream_start

            header = @data[offset...stream_start]

            # Extract trailer-equivalent keys from the stream dictionary
            %w[Root Info Size].each do |key|
              next if @trailer.key?(key)

              value = dict_value(header, key)
              @trailer[key] = value if value
            end

            # Parse /W array (field widths)
            w_text = dict_value(header, 'W')
            return nil unless w_text

            widths = w_text.scan(/\d+/).map(&:to_i)
            return nil unless widths.length == 3

            entry_size = widths.sum
            return nil if entry_size == 0

            # Parse /Index array (subsection ranges), default to [0 Size]
            index_text = dict_value(header, 'Index')
            size_val = dict_value(header, 'Size')
            indices = if index_text
                        index_text.scan(/\d+/).map(&:to_i)
                      else
                        [0, size_val.to_i]
                      end

            # Decompress the stream
            stream_data = read_xref_stream_data(offset, stream_start, header)
            return nil unless stream_data

            # Parse entries
            parse_xref_stream_entries(stream_data, widths, indices)

            prev_val = dict_value(header, 'Prev')
            prev_val ? prev_val.to_i : nil
          rescue Shoko::Error
            nil
          end

          def read_xref_stream_data(offset, stream_start, header)
            pos = stream_start + 6
            pos += 1 if @data.getbyte(pos) == 0x0D
            pos += 1 if @data.getbyte(pos) == 0x0A

            raw = read_stream_bytes(pos, header)
            return nil unless raw

            if header.include?('FlateDecode')
              decompress(raw)
            else
              raw
            end
          end

          def parse_xref_stream_entries(stream_data, widths, indices)
            stream_data.force_encoding(Encoding::BINARY)
            w1, w2, w3 = widths
            entry_size = w1 + w2 + w3
            pos = 0

            # Process each subsection from /Index
            i = 0
            while i < indices.length - 1
              start_num = indices[i]
              count = indices[i + 1]

              count.times do |j|
                break if pos + entry_size > stream_data.length

                type = read_xref_int(stream_data, pos, w1)
                type = 1 if w1 == 0 # default type is 1 when field width is 0
                field2 = read_xref_int(stream_data, pos + w1, w2)
                # field3 = read_xref_int(stream_data, pos + w1 + w2, w3)
                pos += entry_size

                obj_num = start_num + j
                # Type 1: object in use at byte offset field2
                if type == 1 && field2 > 0 && !@xref.key?(obj_num)
                  @xref[obj_num] = field2
                end
                # Type 0: free object, Type 2: compressed object (in object stream) — skip
              end

              i += 2
            end
          end

          def read_xref_int(data, offset, width)
            return 0 if width == 0

            result = 0
            width.times do |i|
              result = (result << 8) | (data.getbyte(offset + i) || 0)
            end
            result
          end

          def collect_pages(pages_obj_num)
            raw = read_object_raw(pages_obj_num)
            return [] unless raw

            # Check if this is a Pages node or a single Page
            type = dict_value(raw, 'Type')

            if type == 'Page'
              [pages_obj_num]
            elsif type == 'Pages'
              kids_text = dict_value(raw, 'Kids')
              return [] unless kids_text

              # Kids may be an indirect reference to an array object
              if kids_text =~ /\A\d+\s+\d+\s+R\z/
                kids_obj_num = resolve_ref(kids_text)
                return [] unless kids_obj_num

                kids_raw = read_object_raw(kids_obj_num)
                return [] unless kids_raw

                kids_text = kids_raw
              end

              refs = kids_text.scan(/(\d+)\s+\d+\s+R/)
              refs.flat_map { |ref| collect_pages(ref[0].to_i) }
            else
              []
            end
          end

          def decompress(raw)
            Zlib::Inflate.inflate(raw)
          rescue Zlib::DataError, Zlib::BufError
            # Try with raw deflate (no zlib header)
            begin
              Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(raw)
            rescue Zlib::DataError, Zlib::BufError
              nil
            end
          end

          def read_stream_bytes(stream_data_start, header)
            length = stream_length_from_header(header)
            if length && length >= 0
              raw = @data.byteslice(stream_data_start, length)
              return raw if raw && raw.bytesize == length
            end

            endstream_idx = @data.index('endstream', stream_data_start)
            return nil unless endstream_idx

            @data[stream_data_start...endstream_idx]
          end

          def stream_length_from_header(header)
            value = dict_value(header, 'Length')
            return nil unless value

            value_text = value.to_s.strip
            return value_text.to_i if value_text.match?(/\A-?\d+\z/)

            ref_obj = resolve_ref(value_text)
            return nil unless ref_obj

            raw = read_object_raw(ref_obj)
            return nil unless raw

            body = raw.sub(/\A.*?\bobj\b/m, '')
            parse_integer(body)
          end

          def parse_integer(text)
            match = text.to_s.match(/-?\d+/)
            match ? match[0].to_i : nil
          end

          def extract_parenthesized(text)
            depth = 0
            i = 0
            while i < text.length
              case text[i]
              when '('
                depth += 1
              when ')'
                depth -= 1
                return text[1...i] if depth == 0
              when '\\'
                i += 1 # skip escaped char
              end
              i += 1
            end
            nil
          end

          def extract_hex_string(text)
            end_idx = text.index('>')
            return nil unless end_idx

            text[1...end_idx]
          end

          def extract_nested_dict(text)
            depth = 0
            i = 0
            while i < text.length - 1
              if text[i] == '<' && text[i + 1] == '<'
                depth += 1
                i += 2
              elsif text[i] == '>' && text[i + 1] == '>'
                depth -= 1
                if depth == 0
                  return text[0..i + 1]
                end

                i += 2
              else
                i += 1
              end
            end
            text
          end

          def extract_array(text)
            depth = 0
            i = 0
            while i < text.length
              case text[i]
              when '['
                depth += 1
              when ']'
                depth -= 1
                return text[1...i] if depth == 0
              end
              i += 1
            end
            nil
          end
        end
      end
    end
  end
end
