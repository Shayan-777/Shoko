# frozen_string_literal: true

module Shoko
  module Core::BookFormats
    # Central registry mapping ebook file extensions to their importer classes,
    # metadata extractors, and content parser factories.
    #
    # Format modules self-register on load:
    #   FormatRegistry.register('.epub', importer_class: EpubImporter, ...)
    #
    # Consumers query:
    #   FormatRegistry.importer_for(path)
    #   FormatRegistry.supported_extension?(path)
    module FormatRegistry
      Entry = Struct.new(:importer_class, :metadata_extractor, :content_parser_factory, keyword_init: true)
      private_constant :Entry

      @formats = {}

      class << self
        # Register a format by its file extension.
        #
        # @param extension [String] e.g. '.epub', '.fb2', '.fb2.zip'
        # @param importer_class [Class, Proc] importer class or zero-arity resolver
        # @param metadata_extractor [Object, Proc, nil] extractor or zero-arity resolver
        # @param content_parser_factory [Proc, nil] ->(raw, logger:) { parser }
        def register(extension, importer_class:, metadata_extractor: nil, content_parser_factory: nil)
          @formats[extension.downcase] = Entry.new(
            importer_class: importer_class,
            metadata_extractor: metadata_extractor,
            content_parser_factory: content_parser_factory
          )
        end

        # Return the importer class for the given file path.
        #
        # @param path [String] file path
        # @return [Class, nil]
        def importer_for(path)
          resolve_entry_value(entry_for(path), :importer_class)
        end

        # Return the metadata extractor for the given file path.
        #
        # @param path [String] file path
        # @return [Object, nil]
        def metadata_extractor_for(path)
          resolve_entry_value(entry_for(path), :metadata_extractor)
        end

        # Return the content parser factory for the given file path.
        #
        # @param path [String] file path
        # @return [Proc, nil]
        def content_parser_factory_for(path)
          resolve_entry_value(entry_for(path), :content_parser_factory)
        end

        # Check if the given file path has a supported ebook extension.
        #
        # @param path [String] file path
        # @return [Boolean]
        def supported_extension?(path)
          !entry_for(path).nil?
        end

        # Return all registered extensions.
        #
        # @return [Array<String>]
        def supported_extensions
          @formats.keys
        end

        # Compatibility helper that checks only registered extensions.
        #
        # @param path [String] file path
        # @return [Boolean]
        def book_file?(path)
          supported_extension?(path)
        end

        # Return the format key (extension) for a path, for tagging chapters.
        #
        # @param path [String]
        # @return [Symbol, nil] e.g. :epub, :fb2
        def format_key_for(path)
          ext = detect_extension(path)
          return nil unless ext

          ext.delete_prefix('.').tr('.', '_').to_sym
        end

        private

        def entry_for(path)
          ext = detect_extension(path)
          return nil unless ext

          @formats[ext]
        end

        # Allow lazy registration values via zero-arity resolvers.
        # This keeps heavyweight format classes out of bootstrap until needed.
        def resolve_entry_value(entry, field)
          return nil unless entry

          value = entry.public_send(field)
          return value unless lazy_resolver?(value)

          resolved = value.call
          entry.public_send("#{field}=", resolved) unless resolved.nil?
          resolved
        end

        def lazy_resolver?(value)
          value.respond_to?(:call) && value.respond_to?(:arity) && value.arity.zero?
        end

        # Detect the registered extension for a path.
        # Tries compound extensions first (e.g. '.fb2.zip') then simple.
        def detect_extension(path)
          lower = path.to_s.downcase
          # Try compound extensions first (longest match)
          @formats.keys.sort_by { |k| -k.length }.each do |ext|
            return ext if lower.end_with?(ext)
          end
          nil
        end
      end
    end
  end
end
