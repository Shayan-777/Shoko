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

        # Streams the response body up to limit bytes; raising aborts the
        # transfer mid-stream instead of buffering an unbounded payload.
        def read(response, limit:)
          buffer = +''
          response.read_body do |chunk|
            buffer << chunk
            raise TooLarge, "Response body exceeded #{limit} bytes" if buffer.bytesize > limit
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
              output << chunk
              raise TooLarge, "Decompressed body exceeded #{limit} bytes" if output.bytesize > limit
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
              output << chunk
              raise TooLarge, "Decompressed body exceeded #{limit} bytes" if output.bytesize > limit
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
