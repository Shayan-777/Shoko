# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Terminal
        class TerminalInput
          # Validates UTF-8 byte sequences.
          class Utf8Validator
            def initialize(bytes)
              @bytes = bytes
            end

            def valid?
              case @bytes.bytesize
              when 2
                valid_2_bytes?
              when 3
                valid_3_bytes?
              when 4
                valid_4_bytes?
              else
                false
              end
            end

            private

            def valid_2_bytes?
              byte_at(1).between?(0x80, 0xBF)
            end

            def valid_3_bytes?
              lead_byte = byte_at(0)
              first_continuation = byte_at(1)
              second_continuation = byte_at(2)
              first_continuation.between?(0x80, 0xBF) &&
                second_continuation.between?(0x80, 0xBF) &&
                !(lead_byte == 0xE0 && first_continuation < 0xA0) &&
                !(lead_byte == 0xED && first_continuation > 0x9F)
            end

            def valid_4_bytes?
              lead_byte = byte_at(0)
              first_continuation = byte_at(1)
              second_continuation = byte_at(2)
              third_continuation = byte_at(3)
              first_continuation.between?(0x80, 0xBF) &&
                second_continuation.between?(0x80, 0xBF) &&
                third_continuation.between?(0x80, 0xBF) &&
                !(lead_byte == 0xF0 && first_continuation < 0x90) &&
                !(lead_byte == 0xF4 && first_continuation > 0x8F)
            end

            def byte_at(index)
              @bytes.getbyte(index)
            end
          end
        end
      end
    end
  end
end
