# frozen_string_literal: true

require_relative '../../shared/errors'

module Shoko
  module Adapters
    module Storage
      # Lazily reads a file into a String on first use.
      #
      # Used to avoid loading large chapter XHTML payloads until they are needed.
      # Optionally sanitizes the loaded content before memoizing it.
      class LazyFileString
        def initialize(path, sanitizer: nil, encoding: Encoding::UTF_8)
          @path = path.to_s
          @sanitizer = sanitizer
          @encoding = encoding
          @loaded = nil
        end

        attr_reader :path

        def to_s
          load_string
        end

        def to_str
          load_string
        end

        def inspect
          "#<#{self.class.name} path=#{path.inspect} loaded=#{!@loaded.nil?}>"
        end

        private

        def load_string
          return @loaded if @loaded

          bytes = File.binread(path)
          bytes.force_encoding(@encoding)
          text = @sanitizer ? @sanitizer.call(bytes) : bytes
          text = text.to_s
          unless text.encoding == Encoding::UTF_8
            text = text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
          end
          @loaded = text
        rescue StandardError => e
          # Translate every load failure into the cache contract's typed error:
          # a missing/unreadable blob (Errno::*) or a bad stored encoding
          # (ArgumentError) is a corrupt-cache condition, not a Shoko::Error.
          raise Shoko::CacheLoadError.new(path, e.message)
        end
      end
    end
  end
end
