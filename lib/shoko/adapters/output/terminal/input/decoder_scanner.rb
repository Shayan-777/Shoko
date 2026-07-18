# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Terminal
        class TerminalInput
          # Scanning helpers for CSI and string terminators.
          class DecoderScanner
            def initialize(buffer)
              @buffer = buffer
            end

            def csi_final_index(start_offset)
              index = start_offset
              while index < @buffer.bytesize
                return index if @buffer.getbyte(index).between?(0x40, 0x7E)

                index += 1
              end
            end

            def string_terminator_index(start_offset)
              start_offset.upto(@buffer.bytesize - 1) do |index|
                length = string_terminator_length(index)
                return index + length if length
              end
            end

            def osc_terminator_index(start_offset)
              start_offset.upto(@buffer.bytesize - 1) do |index|
                length = osc_terminator_length(index)
                return index + length if length
              end
            end

            private

            def string_terminator_length(index)
              case @buffer.getbyte(index)
              when 0x9C
                1
              when 0x1B
                2 if @buffer.getbyte(index + 1) == 0x5C
              end
            end

            def osc_terminator_length(index)
              case @buffer.getbyte(index)
              when 0x07, 0x9C
                1
              when 0x1B
                2 if @buffer.getbyte(index + 1) == 0x5C
              end
            end
          end
        end
      end
    end
  end
end
