# frozen_string_literal: true

require_relative 'stream_offset'
require 'zlib'

require_relative 'reader/dictionary_value_parser'
require_relative 'reader/stream_length_resolver'
require_relative 'reader/stream_predictor'
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
            # obj_num => [object-stream obj_num, index] for objects living inside
            # a compressed object stream (PDF 1.5+ xref type-2 entries).
            @compressed = {}
            @trailer = {}
            @object_cache = {}
            @objstm_cache = {}
            parse_structure
          end

          # Returns the raw text of an object whether it is stored at a direct
          # byte offset (xref type 1) or inside a compressed object stream
          # (xref type 2). Modern PDFs keep most objects — including the page
          # tree — in object streams, so resolving both is required to find pages.
          def read_object_raw(obj_num)
            return @object_cache[obj_num] if @object_cache.key?(obj_num)

            @object_cache[obj_num] = direct_object_raw(obj_num) || compressed_object_raw(obj_num)
          end

          def read_stream(obj_num)
            offset = @xref[obj_num.to_i]
            return nil unless offset

            header, stream_data_start = stream_header_and_data_start(offset)
            return nil unless header

            raw = read_stream_bytes(stream_data_start, header)
            return nil unless raw

            decoded = header.include?('FlateDecode') ? decompress(raw) : raw
            stream_predictor.apply(decoded, header)
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

            collect_pages(pages_num, {})
          end

          private

          def direct_object_raw(obj_num)
            offset = @xref[obj_num.to_i]
            return nil unless offset

            endobj_idx = @data.index('endobj', offset)
            return nil unless endobj_idx

            @data[offset..(endobj_idx + 5)]
          end

          # An object stored inside a compressed object stream. The container
          # /ObjStm is decoded once and its members cached, so reading many
          # objects from one stream costs a single inflate.
          def compressed_object_raw(obj_num)
            entry = @compressed[obj_num.to_i]
            return nil unless entry

            objstm_num, index = entry
            object_stream_members(objstm_num)[index]
          end

          def object_stream_members(objstm_num)
            @objstm_cache[objstm_num] ||= extract_object_stream_members(objstm_num)
          end

          # Parse an /ObjStm: /N is the member count, /First the byte offset where
          # member data begins. The container must be a direct object (guards
          # against a malformed ObjStm-inside-ObjStm cycle).
          def extract_object_stream_members(objstm_num)
            return {} unless @xref.key?(objstm_num.to_i)

            header = read_object_raw(objstm_num)
            return {} unless header

            count = dict_value(header, 'N').to_i
            first = dict_value(header, 'First').to_i
            return {} unless count.positive? && first.positive?

            body = read_stream(objstm_num)
            return {} unless body

            split_object_stream_members(body.b, count, first)
          end

          # The first +first+ bytes are +count+ pairs of "objnum offset" integers;
          # member i spans from +first+ + offset_i to the next member (or the end).
          def split_object_stream_members(body, count, first)
            header_ints = body[0, first].to_s.scan(/\d+/).map(&:to_i)
            members = {}
            count.times do |i|
              start = header_ints[(2 * i) + 1]
              next unless start

              finish = header_ints[(2 * i) + 3]
              members[i] = finish ? body[(first + start)...(first + finish)] : body[(first + start)..]
            end
            members
          end

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

          # +seen+ guards against malformed page trees whose /Kids cycle back to
          # an ancestor (or share a node): without it the recursion never
          # terminates. Each node is expanded at most once.
          def collect_pages(obj_num, seen)
            return [] if seen[obj_num]

            seen[obj_num] = true
            raw = read_object_raw(obj_num)
            return [] unless raw

            case dict_value(raw, 'Type')
            when 'Page'
              [obj_num]
            when 'Pages'
              collect_page_kids(raw, seen)
            else
              []
            end
          end

          def collect_page_kids(raw, seen)
            kids_text = resolved_kids_text(raw)
            return [] unless kids_text

            refs = kids_text.scan(/(\d+)\s+\d+\s+R/)
            refs.flat_map { |ref| collect_pages(ref[0].to_i, seen) }
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

            [@data[offset...stream_start], StreamOffset.data_start(@data, stream_start)]
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
              compressed: @compressed,
              trailer: @trailer,
              dict_value: method(:dict_value),
              read_stream_bytes: method(:read_stream_bytes),
              decompress: method(:decompress),
              predictor: stream_predictor
            )
          end

          def stream_predictor
            @stream_predictor ||= Reader::StreamPredictor.new(dict_value: method(:dict_value))
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
