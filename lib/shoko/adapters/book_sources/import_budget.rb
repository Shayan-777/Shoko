# frozen_string_literal: true

require 'zlib'
require 'rexml/parsers/pullparser'
require 'shoko/shared/errors'

module Shoko
  module Adapters
    module BookSources
      # Per-import resource budget for data controlled by an ebook file.
      #
      # Importers share this policy so a format cannot accidentally omit the
      # limits already applied to its peers. A budget is intentionally scoped
      # to one book: aggregate counters cover every stream, record, resource,
      # and parser object produced while that book is imported.
      class ImportBudget
        DEFAULT_MAX_SOURCE_BYTES = 200 * 1024 * 1024
        DEFAULT_MAX_EXPANDED_ITEM_BYTES = 64 * 1024 * 1024
        DEFAULT_MAX_EXPANDED_BYTES = 256 * 1024 * 1024
        DEFAULT_MAX_RESOURCE_ITEM_BYTES = 64 * 1024 * 1024
        DEFAULT_MAX_RESOURCE_BYTES = 128 * 1024 * 1024
        DEFAULT_MAX_STRUCTURAL_UNITS = 500_000
        DEFAULT_MAX_DECODE_OPERATIONS = 50_000_000
        DEFAULT_MAX_NESTING = 512
        DEFAULT_MAX_DIMENSION_BYTES = 64 * 1024 * 1024
        INFLATE_INPUT_CHUNK_BYTES = 1024
        FILE_READ_CHUNK_BYTES = 64 * 1024

        attr_reader :path, :max_expanded_item_bytes, :max_nesting

        def initialize(path:, max_source_bytes: DEFAULT_MAX_SOURCE_BYTES,
                       max_expanded_item_bytes: DEFAULT_MAX_EXPANDED_ITEM_BYTES,
                       max_expanded_bytes: DEFAULT_MAX_EXPANDED_BYTES,
                       max_resource_item_bytes: DEFAULT_MAX_RESOURCE_ITEM_BYTES,
                       max_resource_bytes: DEFAULT_MAX_RESOURCE_BYTES,
                       max_structural_units: DEFAULT_MAX_STRUCTURAL_UNITS,
                       max_decode_operations: DEFAULT_MAX_DECODE_OPERATIONS,
                       max_nesting: DEFAULT_MAX_NESTING,
                       max_dimension_bytes: DEFAULT_MAX_DIMENSION_BYTES)
          @path = path.to_s
          @max_source_bytes = positive_limit(max_source_bytes, :max_source_bytes)
          @max_expanded_item_bytes = positive_limit(max_expanded_item_bytes, :max_expanded_item_bytes)
          @max_expanded_bytes = positive_limit(max_expanded_bytes, :max_expanded_bytes)
          @max_resource_item_bytes = positive_limit(max_resource_item_bytes, :max_resource_item_bytes)
          @max_resource_bytes = positive_limit(max_resource_bytes, :max_resource_bytes)
          @max_structural_units = positive_limit(max_structural_units, :max_structural_units)
          @max_decode_operations = positive_limit(max_decode_operations, :max_decode_operations)
          @max_nesting = positive_limit(max_nesting, :max_nesting)
          @max_dimension_bytes = positive_limit(max_dimension_bytes, :max_dimension_bytes)
          @expanded_bytes = 0
          @resource_bytes = 0
          @structural_units = 0
          @decode_operations = 0
        end

        def check_source_file!(source_path = path)
          size = File.size(source_path)
          reject!("source exceeds #{@max_source_bytes} bytes") if size > @max_source_bytes
          size
        rescue SystemCallError => e
          raise Shoko::BookParseError.new("unable to inspect source: #{e.message}", source_path)
        end

        def read_binary(source_path = path)
          check_source_file!(source_path)
          output = +''.b
          File.open(source_path, 'rb') do |io|
            while (chunk = io.read(FILE_READ_CHUNK_BYTES))
              if output.bytesize + chunk.bytesize > @max_source_bytes
                reject!("source exceeds #{@max_source_bytes} bytes")
              end

              output << chunk
            end
          end
          output
        rescue Shoko::Error
          raise
        rescue SystemCallError => e
          raise Shoko::BookParseError.new("unable to read source: #{e.message}", source_path)
        end

        def consume_expanded!(byte_count, label: 'expanded data')
          count = nonnegative_count(byte_count, label)
          reject!("#{label} exceeds #{@max_expanded_item_bytes} bytes") if count > @max_expanded_item_bytes
          reject!('book exceeds aggregate expanded-data budget') if @expanded_bytes + count > @max_expanded_bytes

          @expanded_bytes += count
          count
        end

        def consume_resource!(byte_count, label: 'embedded resource')
          count = nonnegative_count(byte_count, label)
          reject!("#{label} exceeds #{@max_resource_item_bytes} bytes") if count > @max_resource_item_bytes
          reject!('book exceeds aggregate embedded-resource budget') if @resource_bytes + count > @max_resource_bytes

          @resource_bytes += count
          count
        end

        def check_resource_item!(byte_count, label: 'embedded resource')
          count = nonnegative_count(byte_count, label)
          reject!("#{label} exceeds #{@max_resource_item_bytes} bytes") if count > @max_resource_item_bytes
          count
        end

        def consume_structure!(count = 1, label: 'document structure')
          units = nonnegative_count(count, label)
          if @structural_units + units > @max_structural_units
            reject!("#{label} exceeds #{@max_structural_units} units")
          end

          @structural_units += units
          units
        end

        def consume_decode_operations!(count, label: 'compressed stream')
          operations = nonnegative_count(count, label)
          if @decode_operations + operations > @max_decode_operations
            reject!("#{label} exceeds decompression work budget")
          end

          @decode_operations += operations
          operations
        end

        def check_nesting!(depth, label: 'document nesting')
          reject!("#{label} exceeds #{@max_nesting} levels") if depth.to_i > @max_nesting
        end

        def check_dimension!(bytes, label: 'decoded row')
          count = nonnegative_count(bytes, label)
          reject!("#{label} exceeds #{@max_dimension_bytes} bytes") if count > @max_dimension_bytes
          count
        end

        def preflight_xml!(xml, label: 'XML document')
          parser = REXML::Parsers::PullParser.new(xml)
          depth = 0
          depth = consume_xml_event(parser.pull, depth, label) while parser.has_next?
          true
        rescue Shoko::Error
          raise
        rescue REXML::ParseException => e
          raise Shoko::BookParseError.new("invalid #{label}: #{e.message}", path)
        end

        def inflate(raw, window_bits: Zlib::MAX_WBITS, label: 'compressed stream')
          inflater = Zlib::Inflate.new(window_bits)
          output = +''.b
          inflate_chunks(inflater, raw.to_s.b, output, label)
          append_inflated!(output, inflater.finish, label)
          consume_expanded!(output.bytesize, label: label)
          output
        ensure
          inflater&.close
        end

        private

        def consume_xml_event(event, depth, label)
          return depth unless event.start_element? || event.end_element? || event.text?

          consume_structure!(1, label: label)
          return [depth - 1, 0].max if event.end_element?
          return depth unless event.start_element?

          next_depth = depth + 1
          check_nesting!(next_depth, label: "#{label} nesting")
          next_depth
        end

        def inflate_chunks(inflater, input, output, label)
          offset = 0
          while offset < input.bytesize
            chunk = input.byteslice(offset, INFLATE_INPUT_CHUNK_BYTES)
            append_inflated!(output, inflater.inflate(chunk), label)
            offset += chunk.bytesize
          end
        end

        def append_inflated!(output, chunk, label)
          return if chunk.empty?

          projected = output.bytesize + chunk.bytesize
          reject!("#{label} exceeds #{@max_expanded_item_bytes} bytes") if projected > @max_expanded_item_bytes
          output << chunk
        end

        def positive_limit(value, name)
          parsed = Integer(value)
          raise ArgumentError, "#{name} must be positive" unless parsed.positive?

          parsed
        end

        def nonnegative_count(value, label)
          parsed = Integer(value)
          raise ArgumentError, "#{label} count must not be negative" if parsed.negative?

          parsed
        end

        def reject!(message)
          raise Shoko::BookParseError.new("import limit exceeded: #{message}", path)
        end
      end
    end
  end
end
