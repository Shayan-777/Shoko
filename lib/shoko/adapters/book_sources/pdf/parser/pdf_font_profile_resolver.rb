# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Pdf
        # Resolves per-page PDF font metadata used by text extraction:
        # - ToUnicode CMap tables
        # - italic/style hints from BaseFont/FontDescriptor
        class PdfFontProfileResolver
          LIGATURE_GLYPHS = { 'f_f' => 'ff', 'f_f_i' => 'ffi', 'f_f_l' => 'ffl', 'f_i' => 'fi', 'f_l' => 'fl' }.freeze

          def initialize(reader:)
            @reader = reader
            @cmap_cache = {}
            @font_profile_cache = {}
          end

          # @return [Hash<String, Hash>] font_name => { cmap:, italic:, base_font: }
          def build_font_profiles(page_raw, _page_obj_num = nil)
            profiles = {}
            font_entries = font_entries_source(page_raw)
            return profiles unless font_entries

            font_entries.scan(%r{/([^\s/<>\[\]()]+)\s+(\d+)\s+\d+\s+R}).each do |name, obj_num|
              profile = load_font_profile(obj_num.to_i)
              profiles[name] = profile if profile
            end

            profiles
          end

          # @return [Hash<String, Hash>] font_name => glyph map
          def build_font_cmaps(page_raw, page_obj_num = nil)
            profiles = build_font_profiles(page_raw, page_obj_num)
            profiles.each_with_object({}) do |(name, profile), cmaps|
              cmap = profile[:cmap]
              cmaps[name] = cmap if cmap && !cmap.empty?
            end
          end

          private

          def find_font_resources(page_raw)
            direct_resources = font_resources_or_embedded(page_raw)
            return direct_resources if direct_resources

            inherit_font_resources(page_raw)
          end

          def font_entries_source(page_raw)
            resources = find_font_resources(page_raw)
            return nil unless resources

            direct_font_entries(resources) || resolved_font_entries(resources) || resources
          end

          def direct_font_entries(resources) = resources[%r{/Font\s*<<(.*?)>>}m, 1]

          def resolved_font_entries(resources)
            font_ref = @reader.dict_value(resources, 'Font')
            font_num = @reader.resolve_ref(font_ref)
            return nil unless font_num

            @reader.read_object_raw(font_num)
          end

          def inherit_font_resources(page_raw)
            parent_ref = @reader.dict_value(page_raw, 'Parent')
            10.times do
              break unless parent_ref

              parent_num = @reader.resolve_ref(parent_ref)
              break unless parent_num

              parent_raw = @reader.read_object_raw(parent_num)
              break unless parent_raw

              inherited_resources = font_resources_or_embedded(parent_raw)
              return inherited_resources if inherited_resources

              parent_ref = @reader.dict_value(parent_raw, 'Parent')
            end
            nil
          end

          def font_resources_or_embedded(raw)
            resources = @reader.dict_value(raw, 'Resources')
            resolved = resolve_resources_reference(resources)
            return resolved if resolved

            raw.include?('/Font') ? raw : nil
          end

          def resolve_resources_reference(resources)
            return nil unless resources
            return resources if resources.include?('/Font')

            res_num = @reader.resolve_ref(resources)
            return nil unless res_num

            res_raw = @reader.read_object_raw(res_num)
            return res_raw if res_raw&.include?('/Font')

            nil
          end

          def load_cmap_for_font(font_obj_num)
            return @cmap_cache[font_obj_num] if @cmap_cache.key?(font_obj_num)

            font_raw = @reader.read_object_raw(font_obj_num)
            return nil unless font_raw

            tounicode_ref = @reader.dict_value(font_raw, 'ToUnicode')
            cmap_num = @reader.resolve_ref(tounicode_ref)
            return nil unless cmap_num

            cmap_stream = @reader.read_stream(cmap_num)
            return nil unless cmap_stream

            cmap = parse_cmap(cmap_stream.dup.force_encoding(Encoding::UTF_8))
            @cmap_cache[font_obj_num] = cmap
            cmap
          end

          def load_font_profile(font_obj_num)
            return @font_profile_cache[font_obj_num] if @font_profile_cache.key?(font_obj_num)

            font_raw = @reader.read_object_raw(font_obj_num)
            return nil unless font_raw

            base_font = @reader.dict_value(font_raw, 'BaseFont').to_s
            encoding_profile = load_encoding_profile(font_raw)
            profile = {
              cmap: load_cmap_for_font(font_obj_num) || {},
              italic: italic_font?(font_raw, base_font),
              bold: bold_font?(font_raw, base_font),
              base_font: base_font,
              base_encoding: encoding_profile[:base_encoding],
              encoding_map: encoding_profile[:encoding_map],
            }
            @font_profile_cache[font_obj_num] = profile
            profile
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
          end

          def bold_font?(font_raw, base_font)
            return true if base_font.match?(/bold|black|heavy|semibold|demibold/i)

            descriptor_ref = @reader.dict_value(font_raw, 'FontDescriptor')
            descriptor_num = @reader.resolve_ref(descriptor_ref)
            return false unless descriptor_num

            descriptor_raw = @reader.read_object_raw(descriptor_num)
            return false unless descriptor_raw

            bold_descriptor?(descriptor_raw)
          end

          # FontDescriptor signals weight two ways: /FontWeight (>= 600 is bold)
          # and the ForceBold flag (bit 19, value 0x40000) in /Flags.
          def bold_descriptor?(descriptor_raw)
            weight = @reader.dict_value(descriptor_raw, 'FontWeight')
            return true if weight && weight.to_i >= 600

            flags = @reader.dict_value(descriptor_raw, 'Flags')
            return false unless flags

            flags.to_i.allbits?(0x40000)
          end

          def parse_cmap(cmap_text)
            {}.tap do |mapping|
              parse_bfchar_sections(cmap_text, mapping)
              parse_bfrange_sections(cmap_text, mapping)
            end
          end

          def load_encoding_profile(font_raw)
            encoding = @reader.dict_value(font_raw, 'Encoding')
            return { base_encoding: nil, encoding_map: {} } unless encoding

            encoding_ref = @reader.resolve_ref(encoding)
            return parse_encoding_definition(@reader.read_object_raw(encoding_ref)) if encoding_ref

            return parse_encoding_definition(encoding) if encoding.include?('/Differences') || encoding.include?('<<')

            { base_encoding: present_text(encoding), encoding_map: {} }
          end

          def parse_encoding_definition(encoding_raw)
            return { base_encoding: nil, encoding_map: {} } unless encoding_raw

            {
              base_encoding: present_text(@reader.dict_value(encoding_raw, 'BaseEncoding')),
              encoding_map: parse_differences(encoding_raw),
            }
          end

          def parse_differences(encoding_raw)
            body = encoding_raw[%r{/Differences\s*\[(.*?)\]}m, 1]
            return {} unless body

            current_code = nil
            body.scan(%r{/([^\s/<>\[\]()]+)|(\d+)}).each_with_object({}) do |(glyph_name, code), mapping|
              if code
                current_code = code.to_i
                next
              end

              next unless current_code

              unicode = glyph_name_to_unicode(glyph_name)
              mapping[current_code] = unicode if unicode
              current_code += 1
            end
          end

          def glyph_name_to_unicode(name)
            return nil unless name
            return LIGATURE_GLYPHS[name] if LIGATURE_GLYPHS.key?(name)
            return name if name.length == 1
            return decode_uni_sequence(name[3..]) if name.start_with?('uni') && ((name.length - 3) % 4).zero?
            return unicode_codepoint(name[1..]) if u_named_glyph?(name)

            nil
          end

          def u_named_glyph?(name) = name.start_with?('u') && name.length.between?(5, 7)

          def decode_uni_sequence(hex) = hex.scan(/.{4}/).filter_map { |chunk| unicode_codepoint(chunk) }.join

          def unicode_codepoint(hex)
            return nil unless hex.match?(/\A[0-9A-Fa-f]{4,6}\z/)

            codepoint = hex.to_i(16)
            return nil unless codepoint.positive? && codepoint <= 0x10FFFF

            [codepoint].pack('U')
          end

          def present_text(value) = (text = value.to_s.strip).empty? ? nil : text

          def parse_bfchar_sections(cmap_text, mapping)
            cmap_text.scan(/beginbfchar\s*(.*?)\s*endbfchar/m).each do |section|
              section[0].scan(/<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>/).each do |glyph_hex, unicode_hex|
                glyph_id = glyph_hex.to_i(16)
                mapping[glyph_id] = hex_to_unicode(unicode_hex)
              end
            end
          end

          def parse_bfrange_sections(cmap_text, mapping)
            cmap_text.scan(/beginbfrange\s*(.*?)\s*endbfrange/m).each do |section|
              pattern = /<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>/
              section[0].scan(pattern).each do |start_hex, end_hex, unicode_start_hex|
                start_id = start_hex.to_i(16)
                end_id = end_hex.to_i(16)
                unicode_start = unicode_start_hex.to_i(16)

                (start_id..end_id).each_with_index do |glyph_id, offset|
                  mapping[glyph_id] = [unicode_start + offset].pack('U')
                end
              end
            end
          end

          def hex_to_unicode(hex_str)
            clean_hex = hex_str.to_s.delete(" \t\r\n")
            if clean_hex.length > 4 && clean_hex.length.even?
              bytes = [clean_hex].pack('H*')
              return bytes.force_encoding(Encoding::UTF_16BE)
                          .encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
            end

            codepoint = clean_hex.to_i(16)
            unless codepoint.positive? && codepoint <= 0x10FFFF
              raise Shoko::BookParseError.new("Invalid PDF Unicode codepoint: #{hex_str}", '')
            end

            [codepoint].pack('U')
          end
        end
      end
    end
  end
end
