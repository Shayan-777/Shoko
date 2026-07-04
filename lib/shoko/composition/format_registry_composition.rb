# frozen_string_literal: true

module Shoko
  module Composition
    # Registers the supported import and parser families with the format registry.
    module FormatRegistryComposition
      module_function

      def register!
        return if @registered

        register_epub
        register_fb2
        register_pdf
        register_kindle
        register_rtf
        @registered = true
      end

      def lazy_resolver(&resolver)
        Shoko::Adapters::BookSources::FormatRegistry::LazyResolver.new(resolver: resolver)
      end
      private_class_method :lazy_resolver

      def register_epub
        register_format(
          '.epub',
          importer_path: '../adapters/book_sources/epub/epub_importer',
          importer_class_name: 'Shoko::Adapters::BookSources::Epub::EpubImporter',
          metadata_path: '../adapters/book_sources/epub/parser/metadata_extractor',
          metadata_class_name: 'Shoko::Adapters::BookSources::Epub::MetadataExtractor',
          parser_path: '../adapters/book_sources/epub/parser/xhtml_content_parser',
          parser_class_name: 'Shoko::Adapters::BookSources::Epub::XHTMLContentParser'
        )
      end
      private_class_method :register_epub

      def register_fb2
        register_extension_family(
          %w[.fb2 .fb2.zip],
          importer_path: '../adapters/book_sources/fb2/fb2_importer',
          importer_class_name: 'Shoko::Adapters::BookSources::Fb2::Fb2Importer',
          metadata_path: '../adapters/book_sources/fb2/parser/fb2_metadata_extractor',
          metadata_class_name: 'Shoko::Adapters::BookSources::Fb2::Fb2MetadataExtractor',
          parser_path: '../adapters/book_sources/fb2/parser/fb2_content_parser',
          parser_class_name: 'Shoko::Adapters::BookSources::Fb2::Fb2ContentParser'
        )
      end
      private_class_method :register_fb2

      def register_pdf
        register_format(
          '.pdf',
          importer_path: '../adapters/book_sources/pdf/pdf_importer',
          importer_class_name: 'Shoko::Adapters::BookSources::Pdf::PdfImporter',
          metadata_path: '../adapters/book_sources/pdf/parser/pdf_metadata_extractor',
          metadata_class_name: 'Shoko::Adapters::BookSources::Pdf::PdfMetadataExtractor',
          parser_path: '../adapters/book_sources/pdf/parser/pdf_content_parser',
          parser_class_name: 'Shoko::Adapters::BookSources::Pdf::PdfContentParser'
        )
      end
      private_class_method :register_pdf

      def register_kindle
        register_extension_family(
          %w[.mobi .azw .azw3],
          importer_path: '../adapters/book_sources/kindle/kindle_importer',
          importer_class_name: 'Shoko::Adapters::BookSources::Kindle::KindleImporter',
          metadata_path: '../adapters/book_sources/kindle/parser/kindle_metadata_extractor',
          metadata_class_name: 'Shoko::Adapters::BookSources::Kindle::KindleMetadataExtractor',
          parser_path: '../adapters/book_sources/kindle/parser/kindle_content_parser',
          parser_class_name: 'Shoko::Adapters::BookSources::Kindle::KindleContentParser'
        )
      end
      private_class_method :register_kindle

      def register_rtf
        register_format(
          '.rtf',
          importer_path: '../adapters/book_sources/rtf/rtf_importer',
          importer_class_name: 'Shoko::Adapters::BookSources::Rtf::RtfImporter',
          metadata_path: '../adapters/book_sources/rtf/parser/rtf_metadata_extractor',
          metadata_class_name: 'Shoko::Adapters::BookSources::Rtf::RtfMetadataExtractor',
          parser_path: '../adapters/book_sources/rtf/parser/rtf_content_parser',
          parser_class_name: 'Shoko::Adapters::BookSources::Rtf::RtfContentParser'
        )
      end
      private_class_method :register_rtf

      def register_extension_family(extensions, **registration)
        extensions.each { |extension| register_format(extension, **registration) }
      end
      private_class_method :register_extension_family

      def register_format(extension, **registration)
        Shoko::Adapters::BookSources::FormatRegistry.register(
          extension,
          importer_class: lazy_importer(registration),
          metadata_extractor: lazy_metadata_extractor(registration),
          content_parser_factory: parser_factory(registration)
        )
      end
      private_class_method :register_format

      def lazy_importer(registration)
        lazy_resolver do
          require_relative registration.fetch(:importer_path)
          Object.const_get(registration.fetch(:importer_class_name))
        end
      end
      private_class_method :lazy_importer

      def lazy_metadata_extractor(registration)
        lazy_resolver do
          require_relative registration.fetch(:metadata_path)
          Object.const_get(registration.fetch(:metadata_class_name))
        end
      end
      private_class_method :lazy_metadata_extractor

      def parser_factory(registration)
        lambda do |raw, logger: nil, style_resolver: nil|
          require_relative registration.fetch(:parser_path)
          Object.const_get(registration.fetch(:parser_class_name))
                .new(raw, logger: logger, style_resolver: style_resolver)
        end
      end
      private_class_method :parser_factory
    end
  end
end
