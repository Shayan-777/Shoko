# frozen_string_literal: true

require 'zlib'

require_relative 'reader/dictionary_value_parser'
require_relative 'reader/stream_length_resolver'
require_relative 'reader/xref_stream_parser'
require_relative 'reader/xref_table_parser'

module Shoko
  module Adapters
    module BookSources
      module Pdf
        # Low-level PDF file reader. Parses xref data, reads objects and streams,
        # and provides helpers for walking the page tree.
        class PdfReader
          attr_reader :data, :xref, :trailer

          def initialize(data)
            @data = data.to_s.dup
            @data.force_encoding(Encoding::BINARY)
            @xref = {}
            @trailer = {}
            @object_cache = {}
            parse_structure
          end

          def read_object_raw(obj_num)
            return @object_cache[obj_num] if @object_cache.key?(obj_num)

            offset = @xref[obj_num.to_i]
            return nil unless offset

            endobj_idx = @data.index('endobj', offset)
            return nil unless endobj_idx

            raw = @data[offset..(endobj_idx + 5)]
            @object_cache[obj_num] = raw
            raw
          end

          def read_stream(obj_num)
            offset = @xref[obj_num.to_i]
            return nil unless offset

            header, stream_data_start = stream_header_and_data_start(offset)
            return nil unless header

            raw = read_stream_bytes(stream_data_start, header)
            return nil unless raw

            header.include?('FlateDecode') ? decompress(raw) : raw
          end

          def resolve_ref(ref_string)
            match = ref_string.to_s.match(/(\d+)\s+\d+\s+R/)
            match ? match[1].to_i : nil
          end

          def dict_value(dict_text, key)
            dictionary_value_parser.parse(dict_text, key)
          end

          def root_obj_num
            resolve_ref(@trailer['Root'])
          end

          def info_obj_num
            resolve_ref(@trailer['Info'])
          end

          def page_object_numbers
            root = read_object_raw(root_obj_num)
            return [] unless root

            pages_num = resolve_ref(dict_value(root, 'Pages'))
            return [] unless pages_num

            collect_pages(pages_num)
          end

          private

          def parse_structure
            startxref_idx = @data.rindex('startxref')
            return unless startxref_idx

            xref_offset = @data[(startxref_idx + 9)..(startxref_idx + 30)].strip.to_i
            parse_xref_chain(xref_offset)
          end

          def parse_xref_chain(offset)
            visited = {}
            current_offset = offset

            while current_offset&.positive? && !visited[current_offset]
              visited[current_offset] = true
              current_offset = parse_xref_section(current_offset)
            end
          end

          def parse_xref_section(offset)
            return parse_xref_stream(offset) unless @data[offset, 4] == 'xref'

            parse_traditional_xref(offset)
            parse_trailer_dict_at(offset)
          end

          def parse_traditional_xref(xref_offset)
            xref_table_parser.parse_table(xref_offset)
          end

          def parse_trailer_dict_at(xref_offset)
            xref_table_parser.parse_trailer(xref_offset)
          end

          def parse_xref_stream(offset)
            xref_stream_parser.parse(offset)
          end

          def parse_xref_stream_entries(stream_data, widths, indices)
            xref_stream_parser.parse_entries(stream_data, widths, indices)
          end

          def collect_pages(obj_num)
            raw = read_object_raw(obj_num)
            return [] unless raw

            case dict_value(raw, 'Type')
            when 'Page'
              [obj_num]
            when 'Pages'
              collect_page_kids(raw)
            else
              []
            end
          end

          def collect_page_kids(raw)
            kids_text = resolved_kids_text(raw)
            return [] unless kids_text

            refs = kids_text.scan(/(\d+)\s+\d+\s+R/)
            refs.flat_map { |ref| collect_pages(ref[0].to_i) }
          end

          def resolved_kids_text(raw)
            kids_text = dict_value(raw, 'Kids')
            return nil unless kids_text
            return kids_text unless kids_text.match?(/\A\d+\s+\d+\s+R\z/)

            kids_obj_num = resolve_ref(kids_text)
            return nil unless kids_obj_num

            read_object_raw(kids_obj_num)
          end

          def decompress(raw)
            Zlib::Inflate.inflate(raw)
          rescue Zlib::DataError, Zlib::BufError
            decompress_raw(raw)
          end

          # If both the zlib-wrapped and raw-deflate attempts fail, the stream
          # is corrupt. Translate the zlib failure into a Shoko book-parse error
          # at its source so the extractor/import boundaries (which rescue
          # Shoko::Error) skip the page or reject the file cleanly, instead of a
          # raw Zlib::DataError escaping the whole import (R4 / §VIII).
          def decompress_raw(raw)
            Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(raw)
          rescue Zlib::DataError, Zlib::BufError => e
            raise Shoko::BookParseError.new("corrupt PDF stream: #{e.message}", '')
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
            stream_length_resolver.resolve(header)
          end

          def stream_header_and_data_start(offset)
            stream_start = @data.index('stream', offset)
            return nil unless stream_start

            endobj_idx = @data.index('endobj', offset)
            return nil unless endobj_idx && stream_start < endobj_idx

            [@data[offset...stream_start], stream_data_start(stream_start)]
          end

          def stream_data_start(stream_start)
            pos = stream_start + 6
            pos += 1 if @data.getbyte(pos) == 0x0D
            pos += 1 if @data.getbyte(pos) == 0x0A
            pos
          end

          def xref_table_parser
            @xref_table_parser ||= Reader::XrefTableParser.new(
              data: @data,
              xref: @xref,
              trailer: @trailer,
              dict_value: method(:dict_value)
            )
          end

          def xref_stream_parser
            @xref_stream_parser ||= Reader::XrefStreamParser.new(
              data: @data,
              xref: @xref,
              trailer: @trailer,
              dict_value: method(:dict_value),
              read_stream_bytes: method(:read_stream_bytes),
              decompress: method(:decompress)
            )
          end

          def stream_length_resolver
            @stream_length_resolver ||= Reader::StreamLengthResolver.new(
              dict_value: method(:dict_value),
              resolve_ref: method(:resolve_ref),
              read_object_raw: method(:read_object_raw)
            )
          end

          def dictionary_value_parser
            @dictionary_value_parser ||= Reader::DictionaryValueParser.new
          end
        end
      end
    end
  end
end
