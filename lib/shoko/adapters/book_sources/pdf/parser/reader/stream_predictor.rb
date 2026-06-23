# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Pdf
        module Reader
          # Reverses the PNG/TIFF predictor that PDFs apply before FlateDecode.
          # Almost every PDF-1.5+ cross-reference stream is encoded with PNG
          # "Up" (Predictor 12); without un-filtering, the inflated bytes parse
          # as garbage offsets and the page tree cannot be found. Object and
          # content streams occasionally use predictors too, so this runs on the
          # decoded bytes of any stream that declares /DecodeParms.
          class StreamPredictor
            def initialize(dict_value:)
              @dict_value = dict_value
            end

            # @param data [String] already FlateDecoded stream bytes
            # @param header [String] the stream's object dictionary text
            # @return [String] data with the predictor reversed (or unchanged)
            def apply(data, header)
              params = decode_parms(header)
              return data unless params

              predictor = @dict_value.call(params, 'Predictor').to_i
              return data if predictor <= 1

              row_len, bpp = row_geometry(params)
              predictor >= 10 ? png_unfilter(data.b, row_len, bpp) : tiff_unfilter(data.b, row_len, bpp)
            end

            private

            def decode_parms(header)
              parms = @dict_value.call(header, 'DecodeParms') || @dict_value.call(header, 'DP')
              return nil unless parms.is_a?(String) && parms.include?('Predictor')

              parms
            end

            # @return [Array(Integer, Integer)] [bytes per row, bytes per pixel]
            def row_geometry(params)
              columns = positive_int(@dict_value.call(params, 'Columns'), 1)
              colors = positive_int(@dict_value.call(params, 'Colors'), 1)
              bpc = positive_int(@dict_value.call(params, 'BitsPerComponent'), 8)
              bpp = [(colors * bpc / 8.0).ceil, 1].max
              row_len = [(columns * colors * bpc / 8.0).ceil, 1].max
              [row_len, bpp]
            end

            def positive_int(value, default)
              parsed = value.to_i
              parsed.positive? ? parsed : default
            end

            # PNG predictors prefix every row with a filter-type byte (0-4) and
            # decode each byte from the reconstructed bytes to its left (a) and
            # above (b), plus the byte above-left (c) for Paeth.
            def png_unfilter(data, row_len, bpp)
              stride = row_len + 1
              prev = ("\x00".b * row_len)
              out = +''.b
              pos = 0
              while pos + stride <= data.bytesize
                filter_type = data.getbyte(pos)
                row = data.byteslice(pos + 1, row_len)
                prev = png_decode_row(filter_type, row, prev, bpp)
                out << prev
                pos += stride
              end
              out
            end

            def png_decode_row(filter_type, row, prev, bpp)
              out = Array.new(row.bytesize, 0)
              row.bytesize.times do |i|
                left = i >= bpp ? out[i - bpp] : 0
                above = prev.getbyte(i) || 0
                corner = i >= bpp ? (prev.getbyte(i - bpp) || 0) : 0
                out[i] = (row.getbyte(i) + png_predict(filter_type, left, above, corner)) & 0xFF
              end
              out.pack('C*')
            end

            def png_predict(filter_type, left, above, corner)
              case filter_type
              when 1 then left
              when 2 then above
              when 3 then (left + above) / 2
              when 4 then paeth(left, above, corner)
              else 0
              end
            end

            def paeth(left, above, corner)
              estimate = left + above - corner
              dist_left = (estimate - left).abs
              dist_above = (estimate - above).abs
              dist_corner = (estimate - corner).abs
              if dist_left <= dist_above && dist_left <= dist_corner then left
              elsif dist_above <= dist_corner then above
              else corner
              end
            end

            # TIFF Predictor 2: each byte adds the reconstructed byte one pixel to
            # its left, within the row only (no per-row filter byte).
            def tiff_unfilter(data, row_len, bpp)
              out = +''.b
              pos = 0
              while pos + row_len <= data.bytesize
                row = data.byteslice(pos, row_len)
                decoded = Array.new(row_len, 0)
                row_len.times do |i|
                  left = i >= bpp ? decoded[i - bpp] : 0
                  decoded[i] = (row.getbyte(i) + left) & 0xFF
                end
                out << decoded.pack('C*')
                pos += row_len
              end
              out
            end
          end
        end
      end
    end
  end
end
