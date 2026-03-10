# frozen_string_literal: true

require_relative '../../../core/validator'
require_relative '../../../adapters/book_sources/format_registry'

module Shoko
  module Adapters
    module Input
      module Validators
        # Validates file paths for ebook files.
        # Ensures paths exist, are readable, and have correct extension.
        #
        # @example
        #   validator = FilePathValidator.new
        #   if validator.validate?("/path/to/book.epub")
        #     # Path is valid
        #   else
        #     puts validator.errors
        #   end
        class FilePathValidator < Core::Validator
          CACHE_EXTENSION = '.cache'

          # Validate a file path
          #
          # @param path [String] File path to validate
          # @return [Boolean] Validation result
          def validate?(path)
            clear_errors

            presence_valid?(path, :path) &&
              exists?(path) &&
              readable?(path) &&
              extension_valid?(path) &&
              not_empty?(path)
          end

          private

          # Check if file exists
          #
          # @param path [String] File path
          # @return [Boolean] true if exists
          def exists?(path)
            return true if File.exist?(path)

            add_error(:path, "file does not exist: #{path}")
            false
          end

          # Check if file is readable
          #
          # @param path [String] File path
          # @return [Boolean] true if readable
          def readable?(path)
            return true if File.readable?(path)

            add_error(:path, "file is not readable: #{path}")
            false
          end

          # Check if file has a supported ebook extension
          #
          # @param path [String] File path
          # @return [Boolean] true if supported
          def extension_valid?(path)
            return true if Shoko::Adapters::BookSources::FormatRegistry.supported_extension?(path)
            return true if File.extname(path.to_s).casecmp(CACHE_EXTENSION).zero?

            supported = Shoko::Adapters::BookSources::FormatRegistry.supported_extensions.join(', ')
            add_error(:path, "file must have a supported ebook extension (#{supported}) or .cache extension")
            false
          end

          # Check if file is not empty
          #
          # @param path [String] File path
          # @return [Boolean] true if not empty
          def not_empty?(path)
            return true if File.size(path).positive?

            add_error(:path, 'file is empty')
            false
          end
        end
      end
    end
  end
end
