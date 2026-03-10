# frozen_string_literal: true

module Shoko
  module Composition
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
        Shoko::Adapters::BookSources::FormatRegistry.register(
          '.epub',
          importer_class: lazy_resolver do
            require_relative '../adapters/book_sources/epub/epub_importer'
            Shoko::Adapters::BookSources::Epub::EpubImporter
          end,
          metadata_extractor: lazy_resolver do
            require_relative '../adapters/book_sources/epub/parser/metadata_extractor'
            Shoko::Adapters::BookSources::Epub::MetadataExtractor
          end,
          content_parser_factory: lambda { |raw, logger: nil|
            require_relative '../adapters/book_sources/epub/parser/xhtml_content_parser'
            Shoko::Adapters::BookSources::Epub::XHTMLContentParser.new(raw, logger: logger)
          }
        )
      end
      private_class_method :register_epub

      def register_fb2
        Shoko::Adapters::BookSources::FormatRegistry.register(
          '.fb2',
          importer_class: lazy_resolver do
            require_relative '../adapters/book_sources/fb2/fb2_importer'
            Shoko::Adapters::BookSources::Fb2::Fb2Importer
          end,
          metadata_extractor: lazy_resolver do
            require_relative '../adapters/book_sources/fb2/parser/fb2_metadata_extractor'
            Shoko::Adapters::BookSources::Fb2::Fb2MetadataExtractor
          end,
          content_parser_factory: lambda { |raw, logger: nil|
            require_relative '../adapters/book_sources/fb2/parser/fb2_content_parser'
            Shoko::Adapters::BookSources::Fb2::Fb2ContentParser.new(raw, logger: logger)
          }
        )
        Shoko::Adapters::BookSources::FormatRegistry.register(
          '.fb2.zip',
          importer_class: lazy_resolver do
            require_relative '../adapters/book_sources/fb2/fb2_importer'
            Shoko::Adapters::BookSources::Fb2::Fb2Importer
          end,
          metadata_extractor: lazy_resolver do
            require_relative '../adapters/book_sources/fb2/parser/fb2_metadata_extractor'
            Shoko::Adapters::BookSources::Fb2::Fb2MetadataExtractor
          end,
          content_parser_factory: lambda { |raw, logger: nil|
            require_relative '../adapters/book_sources/fb2/parser/fb2_content_parser'
            Shoko::Adapters::BookSources::Fb2::Fb2ContentParser.new(raw, logger: logger)
          }
        )
      end
      private_class_method :register_fb2

      def register_pdf
        Shoko::Adapters::BookSources::FormatRegistry.register(
          '.pdf',
          importer_class: lazy_resolver do
            require_relative '../adapters/book_sources/pdf/pdf_importer'
            Shoko::Adapters::BookSources::Pdf::PdfImporter
          end,
          metadata_extractor: lazy_resolver do
            require_relative '../adapters/book_sources/pdf/parser/pdf_metadata_extractor'
            Shoko::Adapters::BookSources::Pdf::PdfMetadataExtractor
          end,
          content_parser_factory: lambda { |raw, logger: nil|
            require_relative '../adapters/book_sources/pdf/parser/pdf_content_parser'
            Shoko::Adapters::BookSources::Pdf::PdfContentParser.new(raw, logger: logger)
          }
        )
      end
      private_class_method :register_pdf

      def register_kindle
        %w[.mobi .azw .azw3].each do |ext|
          Shoko::Adapters::BookSources::FormatRegistry.register(
            ext,
            importer_class: lazy_resolver do
              require_relative '../adapters/book_sources/kindle/kindle_importer'
              Shoko::Adapters::BookSources::Kindle::KindleImporter
            end,
            metadata_extractor: lazy_resolver do
              require_relative '../adapters/book_sources/kindle/parser/kindle_metadata_extractor'
              Shoko::Adapters::BookSources::Kindle::KindleMetadataExtractor
            end,
            content_parser_factory: lambda { |raw, logger: nil|
              require_relative '../adapters/book_sources/kindle/parser/kindle_content_parser'
              Shoko::Adapters::BookSources::Kindle::KindleContentParser.new(raw, logger: logger)
            }
          )
        end
      end
      private_class_method :register_kindle

      def register_rtf
        Shoko::Adapters::BookSources::FormatRegistry.register(
          '.rtf',
          importer_class: lazy_resolver do
            require_relative '../adapters/book_sources/rtf/rtf_importer'
            Shoko::Adapters::BookSources::Rtf::RtfImporter
          end,
          metadata_extractor: lazy_resolver do
            require_relative '../adapters/book_sources/rtf/parser/rtf_metadata_extractor'
            Shoko::Adapters::BookSources::Rtf::RtfMetadataExtractor
          end,
          content_parser_factory: lambda { |raw, logger: nil|
            require_relative '../adapters/book_sources/rtf/parser/rtf_content_parser'
            Shoko::Adapters::BookSources::Rtf::RtfContentParser.new(raw, logger: logger)
          }
        )
      end
      private_class_method :register_rtf
    end
  end
end
