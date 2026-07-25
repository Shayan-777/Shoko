# frozen_string_literal: true

require 'stringio'
require 'zlib'

require_relative '../../shared/errors'

module Shoko
  module Adapters
    module Rss
      # Byte-ceiling enforcement for HTTP response bodies: bounded streaming
      # reads and bounded gzip/deflate decompression. A malicious or broken
      # server must not be able to exhaust memory with an oversized transfer
      # or a decompression bomb; over-limit input raises TooLarge, which the
      # fetchers translate to their FetchError at the adapter boundary.
      module BoundedHttpBody
        class TooLarge < Shoko::Error; end

        DECOMPRESS_CHUNK_BYTES = 64 * 1024

        module_function

        # Reads the response's declared Content-Encoding and decompresses the
        # body under the ceiling, then returns it as UTF-8 text. Both fetchers
        # asked the identical question of the identical response shape, so it
        # is answered here once.
        #
        # Transcoding is part of this boundary, not an afterthought: Net::HTTP
        # hands back ASCII-8BIT bytes, and every consumer downstream (the feed
        # parser, the article extractor, the HTML entity decoder) does regex
        # and String work against UTF-8 literals. Mixing the two raises
        # Encoding::CompatibilityError deep inside the parsers — which is not
        # a Shoko::Error, so it escaped every rescue on the add-feed path and
        # the failure vanished into the relay's debug log.
        def decode(response, limit:)
          body = decompress(response.body.to_s, response['content-encoding'].to_s.downcase, limit: limit)
          to_utf8(body, charset: charset_of(response))
        end

        # Converts a raw body to UTF-8, replacing anything the declared charset
        # cannot represent. Servers mislabel and truncate encodings constantly,
        # so an undecodable body degrades to scrubbed UTF-8 rather than
        # aborting a fetch that otherwise succeeded.
        def to_utf8(body, charset: nil)
          source = charset.to_s.empty? ? 'UTF-8' : charset
          body.dup.force_encoding(source).encode('UTF-8', invalid: :replace, undef: :replace)
        rescue ArgumentError, Encoding::UndefinedConversionError, Encoding::ConverterNotFoundError
          scrubbed_utf8(body)
        end

        # @return [String, nil] charset from the Content-Type header
        def charset_of(response)
          response['content-type'].to_s[/charset\s*=\s*"?([^;"\s]+)/i, 1]
        end

        def scrubbed_utf8(body)
          body.dup.force_encoding('UTF-8').scrub
        end

        # Streams the response body up to limit bytes; the check runs BEFORE
        # each append so the ceiling is hard — an oversized chunk is never
        # buffered, and raising aborts the transfer mid-stream.
        def read(response, limit:)
          buffer = +''
          response.read_body do |chunk|
            raise TooLarge, "Response body exceeded #{limit} bytes" if buffer.bytesize + chunk.bytesize > limit

            buffer << chunk
          end
          buffer
        end

        # Decompresses a gzip/deflate body with an output ceiling. Mirrors
        # the fetchers' historical tolerance: corrupt compressed data falls
        # back to the raw body, but an over-limit expansion always raises.
        def decompress(body, encoding, limit:)
          return body if encoding.empty?
          return bounded_gunzip(body, limit) if encoding.include?('gzip')
          return bounded_inflate(body, limit) if encoding.include?('deflate')

          body
        rescue Zlib::Error
          body
        end

        def bounded_gunzip(body, limit)
          reader = Zlib::GzipReader.new(StringIO.new(body))
          begin
            output = +''
            while (chunk = reader.read(DECOMPRESS_CHUNK_BYTES))
              raise TooLarge, "Decompressed body exceeded #{limit} bytes" if output.bytesize + chunk.bytesize > limit

              output << chunk
            end
            output
          ensure
            reader.close unless reader.closed?
          end
        end

        def bounded_inflate(body, limit)
          inflater = Zlib::Inflate.new
          begin
            output = +''
            inflater.inflate(body) do |chunk|
              raise TooLarge, "Decompressed body exceeded #{limit} bytes" if output.bytesize + chunk.bytesize > limit

              output << chunk
            end
            output
          ensure
            inflater.close unless inflater.closed?
          end
        end
      end
    end
  end
end
