# frozen_string_literal: true

require 'digest'

module Shoko
  module Shared
    # Computes a fast, stable fingerprint for a source ebook file without
    # reading the full file into memory. Intended to validate that a cache
    # entry still corresponds to a local file when avoiding full SHA-256
    # hashing on warm opens.
    module SourceFingerprint
      module_function

      VERSION = 1
      DEFAULT_CHUNK_BYTES = 64 * 1024

      def compute(path, chunk_bytes: DEFAULT_CHUNK_BYTES)
        return nil if path.nil? || path.to_s.empty?
        return nil unless File.file?(path)

        size_bytes = File.size(path)
        chunk = normalize_chunk_bytes(chunk_bytes)
        head, tail = read_boundary_chunks(path, size_bytes, chunk)
        Digest::SHA256.hexdigest(fingerprint_buffer(size_bytes, head, tail))
      end

      def normalize_chunk_bytes(value)
        bytes = Integer(value)
        return DEFAULT_CHUNK_BYTES if bytes <= 0

        bytes
      rescue ArgumentError, TypeError
        DEFAULT_CHUNK_BYTES
      end
      private_class_method :normalize_chunk_bytes

      def read_boundary_chunks(path, size_bytes, chunk)
        File.open(path, 'rb') do |io|
          head = io.read([size_bytes, chunk].min) || ''.b
          tail = read_tail_chunk(io, size_bytes, chunk)
          [head, tail]
        end
      end
      private_class_method :read_boundary_chunks

      def read_tail_chunk(io, size_bytes, chunk)
        return ''.b unless size_bytes > chunk

        io.seek(-[chunk, size_bytes].min, ::IO::SEEK_END)
        io.read([chunk, size_bytes].min) || ''.b
      end
      private_class_method :read_tail_chunk

      def fingerprint_buffer(size_bytes, head, tail)
        buffer = "v#{VERSION}\0#{size_bytes}\0"
        buffer << head
        buffer << "\0"
        buffer << tail
      end
      private_class_method :fingerprint_buffer
    end
  end
end
