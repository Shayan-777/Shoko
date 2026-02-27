# frozen_string_literal: true

module Shoko
  module Core
    module BookFormats
      module Kindle
        # Parses the EXTH (Extended Header) metadata block from a Mobipocket file.
        #
        # EXTH header layout:
        #   Offset  Size  Field
        #   0       4     Identifier ("EXTH")
        #   4       4     Header length (total size including records)
        #   8       4     Record count
        #   12+     var   EXTH records (type + length + data each)
        #
        # Each EXTH record:
        #   Offset  Size  Field
        #   0       4     Record type (UInt32)
        #   4       4     Record length (total including type+length fields)
        #   8       N-8   Record data
        class ExthParser
          EXTH_MAGIC = 'EXTH'

          # Well-known EXTH record type IDs
          AUTHOR           = 100
          PUBLISHER        = 101
          DESCRIPTION      = 103
          ISBN             = 104
          SUBJECT          = 105
          PUBLISHING_DATE  = 106
          CONTRIBUTOR      = 108
          RIGHTS           = 109
          ASIN             = 113
          LANGUAGE         = 524
          UPDATED_TITLE    = 503
          COVER_OFFSET     = 201
          THUMBNAIL_OFFSET = 202
          CREATOR_SOFTWARE = 204

          # String-valued record types
          STRING_TYPES = [
            AUTHOR, PUBLISHER, DESCRIPTION, ISBN, SUBJECT,
            PUBLISHING_DATE, CONTRIBUTOR, RIGHTS, ASIN, LANGUAGE,
            UPDATED_TITLE, CREATOR_SOFTWARE
          ].freeze

          # @return [Hash{Integer => Array<String>}] parsed records keyed by type ID
          attr_reader :records

          # @param data [String] raw bytes starting at the EXTH header
          # @param encoding_name [String] text encoding for string values (default UTF-8)
          def initialize(data, encoding_name: 'UTF-8')
            @data = data.b
            @encoding_name = encoding_name
            @records = {}
            parse
          end

          # @return [String, nil] author name(s)
          def author
            first_string(AUTHOR)
          end

          # @return [Array<String>] all author entries
          def authors
            strings(AUTHOR)
          end

          # @return [String, nil] updated title (preferred over MOBI full name)
          def updated_title
            first_string(UPDATED_TITLE)
          end

          # @return [String, nil] publisher
          def publisher
            first_string(PUBLISHER)
          end

          # @return [String, nil] description
          def description
            first_string(DESCRIPTION)
          end

          # @return [String, nil] ISBN
          def isbn
            first_string(ISBN)
          end

          # @return [String, nil] publishing date
          def publishing_date
            first_string(PUBLISHING_DATE)
          end

          # @return [String, nil] language
          def language
            first_string(LANGUAGE)
          end

          # @return [String, nil] ASIN
          def asin
            first_string(ASIN)
          end

          # @return [String, nil] subject/genre
          def subject
            first_string(SUBJECT)
          end

          private

          def parse
            return if @data.bytesize < 12

            magic = @data.byteslice(0, 4)
            return unless magic == EXTH_MAGIC

            record_count = @data.byteslice(8, 4).unpack1('N')
            offset = 12

            record_count.times do
              break if offset + 8 > @data.bytesize

              type = @data.byteslice(offset, 4).unpack1('N')
              length = @data.byteslice(offset + 4, 4).unpack1('N')

              # Sanity check: length must be at least 8 (type + length fields)
              break if length < 8 || offset + length > @data.bytesize

              data_length = length - 8
              raw_value = @data.byteslice(offset + 8, data_length)

              value = if STRING_TYPES.include?(type)
                        decode_string(raw_value)
                      else
                        raw_value
                      end

              (@records[type] ||= []) << value
              offset += length
            end
          end

          def decode_string(raw)
            raw.force_encoding(@encoding_name)
            raw.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').strip
          rescue StandardError
            raw.force_encoding('UTF-8')
            raw.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').strip
          end

          def first_string(type)
            values = @records[type]
            return nil unless values&.any?

            val = values.first
            val.is_a?(String) && !val.empty? ? val : nil
          end

          def strings(type)
            values = @records[type]
            return [] unless values

            values.select { |v| v.is_a?(String) && !v.empty? }
          end
        end
      end
    end
  end
end
