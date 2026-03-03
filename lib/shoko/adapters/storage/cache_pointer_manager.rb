# frozen_string_literal: true

require 'json'

require_relative 'atomic_file_writer'

module Shoko
  module Adapters
    module Storage
      # Manages pointer files that reference serialized cache payloads on disk.
      class CachePointerManager
        POINTER_FORMAT = 'shoko-cache'
        LEGACY_POINTER_FORMATS = %w[reader-cache reader-marshal-cache].freeze
        POINTER_VERSION = 2
        POINTER_KEYS    = %w[format version sha256 source_path generated_at engine].freeze
        SUPPORTED_FORMATS = [POINTER_FORMAT, *LEGACY_POINTER_FORMATS].freeze
        SUPPORTED_ENGINES = %w[json marshal].freeze
        SHA256_HEX_PATTERN = /\A[0-9a-f]{64}\z/i

        def initialize(path, logger: nil)
          @path = path
          @logger = logger
        end

        attr_reader :path

        def read
          return nil unless File.exist?(path)

          content = File.read(path)
          return nil if content.nil? || content.empty?

          data = JSON.parse(content)
          return nil unless valid_pointer?(data)

          data
        rescue JSON::ParserError
          raise
        end

        def write(data)
          AtomicFileWriter.write_using(path) do |io|
            io.write(JSON.generate(data))
          end
        rescue Shoko::Error => e
          @logger&.debug('CachePointerManager: write failed', path:, error: e.message)
          false
        end

        private

        def valid_pointer?(data)
          POINTER_KEYS.all? { |key| data.key?(key) } &&
            SUPPORTED_FORMATS.include?(data['format'].to_s) &&
            SUPPORTED_ENGINES.include?(data['engine'].to_s) &&
            data['version'].to_i == POINTER_VERSION &&
            data['sha256'].to_s.match?(SHA256_HEX_PATTERN)
        end
      end
    end
  end
end
