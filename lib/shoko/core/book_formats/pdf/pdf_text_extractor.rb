# frozen_string_literal: true

require_relative 'pdf_reader'

module Shoko
  module Core
    module BookFormats
      module Pdf
        # Extracts readable Unicode text from PDF page content streams by:
        # 1. Building font CMap tables (glyph ID → Unicode) from ToUnicode streams
        # 2. Parsing content stream operators (BT/ET, Tf, Tj, TJ, Td, Tm)
        # 3. Detecting line breaks via vertical position changes
        class PdfTextExtractor
          # @param reader [PdfReader]
          def initialize(reader)
            @reader = reader
            @cmap_cache = {}
            @font_profile_cache = {}
          end

          # Extract text from a single page.
          # @param page_obj_num [Integer]
          # @return [String] extracted text
          def extract_page_text(page_obj_num)
            page_raw = @reader.read_object_raw(page_obj_num)
            return '' unless page_raw

            font_profiles = build_font_profiles(page_raw, page_obj_num)
            stream = read_page_content_stream(page_raw)
            return '' unless stream && !stream.empty?

            stream.force_encoding(Encoding::BINARY)
            raw_lines = parse_content_stream_lines(stream, font_profiles)
            assemble_paragraphs(raw_lines)
          rescue StandardError
            ''
          end

          # Extract line-level layout metadata for a page so downstream parsers can
          # preserve alignment and typographic hints.
          #
          # @param page_obj_num [Integer]
          # @return [Array<Hash>] e.g. [{ text:, x:, italic: }]
          def extract_page_layout(page_obj_num)
            page_raw = @reader.read_object_raw(page_obj_num)
            return [] unless page_raw

            font_profiles = build_font_profiles(page_raw, page_obj_num)
            stream = read_page_content_stream(page_raw)
            return [] unless stream && !stream.empty?

            stream.force_encoding(Encoding::BINARY)
            raw_lines = parse_content_stream_lines(stream, font_profiles)
            raw_lines.map do |line|
              {
                text: line[:text].to_s,
                x: line[:x],
                italic: !!line[:italic],
                italic_ratio: line[:italic_ratio],
              }
            end
          rescue StandardError
            []
          end

          private

          # Read the content stream(s) for a page.
          # /Contents can be a single stream reference or an array of references.
          # @return [String, nil]
          def read_page_content_stream(page_raw)
            content_val = @reader.dict_value(page_raw, 'Contents')
            return nil unless content_val

            # Check if it's a single reference or contains multiple references
            refs = content_val.scan(/(\d+)\s+\d+\s+R/)
            return nil if refs.empty?

            if refs.length == 1
              stream = @reader.read_stream(refs[0][0].to_i)
              return stream
            end

            # Multiple content streams — concatenate them with a space separator
            parts = refs.filter_map do |ref|
              @reader.read_stream(ref[0].to_i)
            end
            parts.empty? ? nil : parts.join(' '.b)
          end

          # Build CMap tables for all fonts referenced in the page's Resources.
          # Walks up the page tree to find inherited Resources if the page lacks its own.
          # @return [Hash<String, Hash>] font_name → {glyph_id → unicode_char}
          def build_font_cmaps(page_raw, page_obj_num = nil)
            profiles = build_font_profiles(page_raw, page_obj_num)
            profiles.each_with_object({}) do |(name, profile), cmaps|
              cmap = profile[:cmap]
              cmaps[name] = cmap if cmap && !cmap.empty?
            end
          end

          # Build font profiles (cmap + style hints) for all page fonts.
          #
          # @return [Hash<String, Hash>] font_name => { cmap:, italic:, base_font: }
          def build_font_profiles(page_raw, page_obj_num = nil)
            profiles = {}
            font_section = find_font_resources(page_raw, page_obj_num)
            return profiles unless font_section

            # Find all font references: /F4 670 0 R
            font_section.scan(/\/(F\d+)\s+(\d+)\s+\d+\s+R/).each do |name, obj_num|
              profile = load_font_profile(obj_num.to_i)
              profiles[name] = profile if profile
            end

            profiles
          end

          # Find the font resources for a page, including inherited from parent Pages.
          def find_font_resources(page_raw, page_obj_num)
            # Try the page's own Resources first
            resources = @reader.dict_value(page_raw, 'Resources')
            if resources
              return resources if resources.include?('/Font')

              # Resources exists but no Font — try resolving if it's a reference
              res_num = @reader.resolve_ref(resources)
              if res_num
                res_raw = @reader.read_object_raw(res_num)
                return res_raw if res_raw&.include?('/Font')
              end
            end

            # Check the page_raw itself (sometimes fonts are inline)
            return page_raw if page_raw.include?('/Font')

            # Walk up to parent Pages node for inherited Resources
            inherit_font_resources(page_raw)
          end

          # Walk up the page tree via /Parent to find inherited font Resources.
          def inherit_font_resources(page_raw)
            parent_ref = @reader.dict_value(page_raw, 'Parent')
            safety = 0
            while parent_ref && safety < 10
              safety += 1
              parent_num = @reader.resolve_ref(parent_ref)
              break unless parent_num

              parent_raw = @reader.read_object_raw(parent_num)
              break unless parent_raw

              resources = @reader.dict_value(parent_raw, 'Resources')
              if resources
                return resources if resources.include?('/Font')

                res_num = @reader.resolve_ref(resources)
                if res_num
                  res_raw = @reader.read_object_raw(res_num)
                  return res_raw if res_raw&.include?('/Font')
                end
              end

              return parent_raw if parent_raw.include?('/Font')

              parent_ref = @reader.dict_value(parent_raw, 'Parent')
            end
            nil
          end

          # Load ToUnicode CMap for a given font object.
          def load_cmap_for_font(font_obj_num)
            return @cmap_cache[font_obj_num] if @cmap_cache.key?(font_obj_num)

            font_raw = @reader.read_object_raw(font_obj_num)
            return nil unless font_raw

            tounicode_ref = @reader.dict_value(font_raw, 'ToUnicode')
            cmap_num = @reader.resolve_ref(tounicode_ref)
            return nil unless cmap_num

            cmap_stream = @reader.read_stream(cmap_num)
            return nil unless cmap_stream

            cmap = parse_cmap(cmap_stream.force_encoding(Encoding::UTF_8))
            @cmap_cache[font_obj_num] = cmap
            cmap
          end

          def load_font_profile(font_obj_num)
            return @font_profile_cache[font_obj_num] if @font_profile_cache.key?(font_obj_num)

            font_raw = @reader.read_object_raw(font_obj_num)
            return nil unless font_raw

            base_font = @reader.dict_value(font_raw, 'BaseFont').to_s
            italic = italic_font?(font_raw, base_font)
            profile = {
              cmap: load_cmap_for_font(font_obj_num) || {},
              italic: italic,
              base_font: base_font,
            }
            @font_profile_cache[font_obj_num] = profile
            profile
          rescue StandardError
            nil
          end

          def italic_font?(font_raw, base_font)
            return true if base_font.match?(/italic|oblique/i)

            descriptor_ref = @reader.dict_value(font_raw, 'FontDescriptor')
            descriptor_num = @reader.resolve_ref(descriptor_ref)
            return false unless descriptor_num

            descriptor_raw = @reader.read_object_raw(descriptor_num)
            return false unless descriptor_raw

            angle = @reader.dict_value(descriptor_raw, 'ItalicAngle')
            angle.to_f.abs > 0.1
          rescue StandardError
            false
          end

          # Parse a CMap stream into a mapping table.
          # @param cmap_text [String]
          # @return [Hash<Integer, String>] glyph_id → unicode_string
          def parse_cmap(cmap_text)
            mapping = {}

            # Parse beginbfchar sections
            cmap_text.scan(/beginbfchar\s*(.*?)\s*endbfchar/m).each do |section|
              section[0].scan(/<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>/).each do |glyph_hex, unicode_hex|
                glyph_id = glyph_hex.to_i(16)
                mapping[glyph_id] = hex_to_unicode(unicode_hex)
              end
            end

            # Parse beginbfrange sections
            cmap_text.scan(/beginbfrange\s*(.*?)\s*endbfrange/m).each do |section|
              section[0].scan(/<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>/).each do |start_hex, end_hex, unicode_start_hex|
                start_id = start_hex.to_i(16)
                end_id = end_hex.to_i(16)
                unicode_start = unicode_start_hex.to_i(16)

                (start_id..end_id).each_with_index do |glyph_id, offset|
                  mapping[glyph_id] = [unicode_start + offset].pack('U')
                end
              end
            end

            mapping
          end

          # Parse a PDF content stream into line-level text fragments.
          # Keeps per-line x-position and italic style hints for layout-aware parsing.
          #
          # @param stream [String] decompressed content stream
          # @param font_profiles [Hash<String, Hash>] font profiles
          # @return [Array<Hash>] [{ text:, x:, italic: }]
          def parse_content_stream_lines(stream, font_profiles)
            raw_lines = []
            current_line = +''
            current_cmap = nil
            current_font_italic = false
            line_style_stats = empty_line_style_stats
            last_y = nil
            current_x = nil
            operand_stack = []

            pos = 0
            while pos < stream.length
              pos += 1 while pos < stream.length && " \t\r\n".include?(stream[pos])
              break if pos >= stream.length

              case stream[pos]
              when '/'
                name_end = stream.index(/[\s\/<>\[\]()]/, pos + 1) || stream.length
                operand_stack << { type: :name, value: stream[pos + 1...name_end] }
                pos = name_end
              when '<'
                if stream[pos + 1] == '<'
                  pos = skip_nested_dict(stream, pos)
                else
                  end_pos = stream.index('>', pos + 1)
                  break unless end_pos

                  operand_stack << { type: :hex, value: stream[pos + 1...end_pos] }
                  pos = end_pos + 1
                end
              when '('
                str = extract_literal_string(stream, pos)
                operand_stack << { type: :literal, value: str }
                pos = skip_literal_string(stream, pos)
              when '['
                array_end = find_matching_bracket(stream, pos)
                break unless array_end

                operand_stack << { type: :array, value: stream[pos + 1...array_end] }
                pos = array_end + 1
              when '-', '+', '.', '0'..'9'
                token_end = stream.index(/[^\d.eE\-+]/, pos + 1) || stream.length
                operand_stack << { type: :number, value: stream[pos...token_end].to_f }
                pos = token_end
              else
                token_end = stream.index(/[\s\/<>\[\]()]/, pos) || stream.length
                op = stream[pos...token_end]
                pos = token_end

                case op
                when 'Tf'
                  _size_op = operand_stack.pop
                  name_op = operand_stack.pop
                  if name_op && name_op[:type] == :name
                    profile = font_profiles[name_op[:value]] || {}
                    current_cmap = profile[:cmap]
                    current_font_italic = !!profile[:italic]
                  end
                when 'Tj'
                  str_op = operand_stack.pop
                  if str_op
                    if str_op[:type] == :hex
                      text = decode_hex_string(str_op[:value], current_cmap)
                      append_text_fragment(current_line, text,
                                           italic: current_font_italic, style_stats: line_style_stats)
                    elsif str_op[:type] == :literal
                      text = decode_literal_string(str_op[:value])
                      append_text_fragment(current_line, text,
                                           italic: current_font_italic, style_stats: line_style_stats)
                    end
                  end
                when 'TJ'
                  arr_op = operand_stack.pop
                  if arr_op && arr_op[:type] == :array
                    text = decode_tj_array(arr_op[:value], current_cmap)
                    append_text_fragment(current_line, text,
                                         italic: current_font_italic, style_stats: line_style_stats)
                  end
                when "'"
                  flush_line(raw_lines, current_line, current_x, line_style_stats) do |next_line, next_stats|
                    current_line = next_line
                    line_style_stats = next_stats
                  end
                  str_op = operand_stack.pop
                  if str_op
                    if str_op[:type] == :hex
                      text = decode_hex_string(str_op[:value], current_cmap)
                      append_text_fragment(current_line, text,
                                           italic: current_font_italic, style_stats: line_style_stats)
                    elsif str_op[:type] == :literal
                      text = decode_literal_string(str_op[:value])
                      append_text_fragment(current_line, text,
                                           italic: current_font_italic, style_stats: line_style_stats)
                    end
                  end
                when 'Td', 'TD'
                  ty_op = operand_stack.pop
                  tx_op = operand_stack.pop
                  ty = ty_op && ty_op[:type] == :number ? ty_op[:value] : 0.0
                  if ty.abs > 0.01
                    flush_line(raw_lines, current_line, current_x, line_style_stats) do |next_line, next_stats|
                      current_line = next_line
                      line_style_stats = next_stats
                    end
                    last_y = (last_y || 0.0) + ty
                    current_x = tx_op && tx_op[:type] == :number ? tx_op[:value] : current_x
                  end
                when 'Tm'
                  ops = pop_n(operand_stack, 6)
                  new_x = ops[4] && ops[4][:type] == :number ? ops[4][:value] : nil
                  new_y = ops[5] && ops[5][:type] == :number ? ops[5][:value] : nil
                  if new_y && last_y && (new_y - last_y).abs > 0.5
                    flush_line(raw_lines, current_line, current_x, line_style_stats) do |next_line, next_stats|
                      current_line = next_line
                      line_style_stats = next_stats
                    end
                  end
                  last_y = new_y if new_y
                  current_x = new_x if new_x
                when "T*"
                  flush_line(raw_lines, current_line, current_x, line_style_stats) do |next_line, next_stats|
                    current_line = next_line
                    line_style_stats = next_stats
                  end
                when 'BT'
                  operand_stack.clear
                when 'ET'
                  operand_stack.clear
                else
                  operand_stack.clear
                end
              end
            end

            flush_line(raw_lines, current_line, current_x, line_style_stats) do |next_line, next_stats|
              current_line = next_line
              line_style_stats = next_stats
            end
            raw_lines
          end

          # Each raw_line is [text, x_position].
          # Detect the baseline X (most common), and insert paragraph breaks when
          # a line starts at a significantly larger X (indented paragraph start).
          def assemble_paragraphs(raw_lines)
            return '' if raw_lines.empty?

            # Determine baseline X from frequency
            x_values = raw_lines.map { |line| line[:x]&.round(0) }.compact
            baseline_x = x_values.min || 0

            result = +''
            raw_lines.each do |line|
              text = line[:text]
              x = line[:x]
              next if text.strip.empty?

              if !result.empty? && x && (x - baseline_x) > 5
                # Indented line → paragraph break
                result << "\n\n" << text.strip
              elsif result.empty?
                result << text.strip
              else
                result << "\n" << text.strip
              end
            end
            result
          end

          def flush_line(raw_lines, current_line, current_x, style_stats)
            unless current_line.strip.empty?
              ratio = italic_ratio_for(style_stats)
              raw_lines << {
                text: current_line.strip,
                x: current_x,
                italic: italic_dominant?(style_stats),
                italic_ratio: ratio,
              }
              yield +'', empty_line_style_stats
            else
              yield current_line, style_stats
            end
          end

          def append_text_fragment(current_line, text, italic:, style_stats:)
            fragment = text.to_s
            return if fragment.empty?

            current_line << fragment
            visible_chars = fragment.scan(/\S/).length
            return if visible_chars.zero?

            style_stats[:total_chars] += visible_chars
            style_stats[:italic_chars] += visible_chars if italic
          end

          def empty_line_style_stats
            { total_chars: 0, italic_chars: 0 }
          end

          def italic_ratio_for(style_stats)
            total = style_stats[:total_chars].to_i
            return 0.0 if total <= 0

            (style_stats[:italic_chars].to_f / total).round(4)
          end

          def italic_dominant?(style_stats)
            total = style_stats[:total_chars].to_i
            return false if total < 8

            italic_ratio_for(style_stats) >= 0.65
          end

          def pop_n(stack, n)
            result = stack.last(n)
            count = [n, stack.size].min
            stack.pop(count)
            result
          end

          def decode_hex_string(hex, cmap)
            return hex_fallback(hex) unless cmap

            text = +''
            i = 0
            clean_hex = hex.gsub(/\s+/, '')
            while i < clean_hex.length
              # Try 4-digit (2-byte) glyph IDs first
              if i + 4 <= clean_hex.length
                glyph_id = clean_hex[i, 4].to_i(16)
                char = cmap[glyph_id]
                if char
                  text << char
                  i += 4
                  next
                end
              end

              # Fall back to 2-digit (1-byte)
              if i + 2 <= clean_hex.length
                glyph_id = clean_hex[i, 2].to_i(16)
                char = cmap[glyph_id]
                if char
                  text << char
                  i += 2
                  next
                end
              end

              i += 4 # skip unknown glyph
            end
            text
          end

          def hex_fallback(hex)
            # Without a CMap, try to interpret as raw bytes
            [hex].pack('H*').force_encoding('UTF-8')
          rescue StandardError
            ''
          end

          def decode_literal_string(str)
            str.to_s
                .gsub('\\n', "\n")
                .gsub('\\r', "\r")
                .gsub('\\t', "\t")
                .gsub('\\(', '(')
                .gsub('\\)', ')')
                .gsub('\\\\', '\\')
          end

          def decode_tj_array(array_content, cmap)
            text = +''
            # TJ arrays contain hex strings and numbers: [<hex> num <hex> num ...]
            array_content.scan(/<([0-9a-fA-F\s]+)>|(\([^)]*\))|(-?[\d.]+)/).each do |hex, literal, num|
              if hex
                text << decode_hex_string(hex, cmap)
              elsif literal
                text << decode_literal_string(literal[1..-2])
              elsif num
                # Large negative numbers indicate word spacing
                text << ' ' if num.to_f < -100
              end
            end
            text
          end

          def hex_to_unicode(hex_str)
            codepoint = hex_str.to_i(16)
            [codepoint].pack('U')
          rescue StandardError
            ''
          end

          def extract_literal_string(stream, pos)
            depth = 0
            i = pos
            while i < stream.length
              case stream[i]
              when '(' then depth += 1
              when ')'
                depth -= 1
                return stream[pos + 1...i] if depth == 0
              when '\\'
                i += 1
              end
              i += 1
            end
            ''
          end

          def skip_literal_string(stream, pos)
            depth = 0
            i = pos
            while i < stream.length
              case stream[i]
              when '(' then depth += 1
              when ')'
                depth -= 1
                return i + 1 if depth == 0
              when '\\'
                i += 1
              end
              i += 1
            end
            stream.length
          end

          def find_matching_bracket(stream, pos)
            depth = 0
            i = pos
            while i < stream.length
              case stream[i]
              when '[' then depth += 1
              when ']'
                depth -= 1
                return i if depth == 0
              when '(' # skip literal strings inside arrays
                i = skip_literal_string(stream, i)
                next
              end
              i += 1
            end
            nil
          end

          def skip_nested_dict(stream, pos)
            depth = 0
            i = pos
            while i < stream.length - 1
              if stream[i] == '<' && stream[i + 1] == '<'
                depth += 1
                i += 2
              elsif stream[i] == '>' && stream[i + 1] == '>'
                depth -= 1
                return i + 2 if depth == 0

                i += 2
              else
                i += 1
              end
            end
            stream.length
          end
        end
      end
    end
  end
end
