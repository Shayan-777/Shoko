# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Pdf
        # Locates the first byte of a PDF stream's payload.
        #
        # Per the PDF spec the `stream` keyword is followed by either CRLF or a
        # single LF before the data begins. Both the document reader and the
        # xref-stream parser have to skip exactly that, and skipping a
        # different number of bytes corrupts every object read afterwards.
        module StreamOffset
          KEYWORD_LENGTH = 6 # "stream"
          CR = 0x0D
          LF = 0x0A

          module_function

          # @param data [String] the raw PDF bytes
          # @param stream_start [Integer] offset of the `stream` keyword
          # @return [Integer] offset of the first payload byte
          def data_start(data, stream_start)
            pos = stream_start + KEYWORD_LENGTH
            pos += 1 if data.getbyte(pos) == CR
            pos += 1 if data.getbyte(pos) == LF
            pos
          end
        end
      end
    end
  end
end
