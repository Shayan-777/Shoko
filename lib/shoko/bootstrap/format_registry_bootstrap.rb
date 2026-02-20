# frozen_string_literal: true

module Shoko
  module Bootstrap
        module FormatRegistryBootstrap
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

          def register_epub
            Shoko::Core::BookFormats::FormatRegistry.register(
              '.epub',
              importer_class: lambda {
                require_relative '../adapters/book_sources/epub/epub_importer'
                Shoko::Adapters::BookSources::Epub::EpubImporter
              },
              metadata_extractor: lambda {
                require_relative '../core/book_formats/epub/metadata_extractor'
                Shoko::Core::BookFormats::Epub::MetadataExtractor
              },
              content_parser_factory: lambda { |raw, logger: nil|
                require_relative '../core/book_formats/epub/xhtml_content_parser'
                Shoko::Core::BookFormats::Epub::XHTMLContentParser.new(raw, logger: logger)
              }
            )
          end
          private_class_method :register_epub

          def register_fb2
            Shoko::Core::BookFormats::FormatRegistry.register(
              '.fb2',
              importer_class: lambda {
                require_relative '../adapters/book_sources/fb2/fb2_importer'
                Shoko::Adapters::BookSources::Fb2::Fb2Importer
              },
              metadata_extractor: lambda {
                require_relative '../core/book_formats/fb2/fb2_metadata_extractor'
                Shoko::Core::BookFormats::Fb2::Fb2MetadataExtractor
              },
              content_parser_factory: lambda { |raw, logger: nil|
                require_relative '../core/book_formats/fb2/fb2_content_parser'
                Shoko::Core::BookFormats::Fb2::Fb2ContentParser.new(raw, logger: logger)
              }
            )
            Shoko::Core::BookFormats::FormatRegistry.register(
              '.fb2.zip',
              importer_class: lambda {
                require_relative '../adapters/book_sources/fb2/fb2_importer'
                Shoko::Adapters::BookSources::Fb2::Fb2Importer
              },
              metadata_extractor: lambda {
                require_relative '../core/book_formats/fb2/fb2_metadata_extractor'
                Shoko::Core::BookFormats::Fb2::Fb2MetadataExtractor
              },
              content_parser_factory: lambda { |raw, logger: nil|
                require_relative '../core/book_formats/fb2/fb2_content_parser'
                Shoko::Core::BookFormats::Fb2::Fb2ContentParser.new(raw, logger: logger)
              }
            )
          end
          private_class_method :register_fb2

          def register_pdf
            Shoko::Core::BookFormats::FormatRegistry.register(
              '.pdf',
              importer_class: lambda {
                require_relative '../adapters/book_sources/pdf/pdf_importer'
                Shoko::Adapters::BookSources::Pdf::PdfImporter
              },
              metadata_extractor: lambda {
                require_relative '../core/book_formats/pdf/pdf_metadata_extractor'
                Shoko::Core::BookFormats::Pdf::PdfMetadataExtractor
              },
              content_parser_factory: lambda { |raw, logger: nil|
                require_relative '../core/book_formats/pdf/pdf_content_parser'
                Shoko::Core::BookFormats::Pdf::PdfContentParser.new(raw, logger: logger)
              }
            )
          end
          private_class_method :register_pdf

          def register_kindle
            %w[.mobi .azw .azw3].each do |ext|
              Shoko::Core::BookFormats::FormatRegistry.register(
                ext,
                importer_class: lambda {
                  require_relative '../adapters/book_sources/kindle/kindle_importer'
                  Shoko::Adapters::BookSources::Kindle::KindleImporter
                },
                metadata_extractor: lambda {
                  require_relative '../core/book_formats/kindle/kindle_metadata_extractor'
                  Shoko::Core::BookFormats::Kindle::KindleMetadataExtractor
                },
                content_parser_factory: lambda { |raw, logger: nil|
                  require_relative '../core/book_formats/kindle/kindle_content_parser'
                  Shoko::Core::BookFormats::Kindle::KindleContentParser.new(raw, logger: logger)
                }
              )
            end
          end
          private_class_method :register_kindle

          def register_rtf
            Shoko::Core::BookFormats::FormatRegistry.register(
              '.rtf',
              importer_class: lambda {
                require_relative '../adapters/book_sources/rtf/rtf_importer'
                Shoko::Adapters::BookSources::Rtf::RtfImporter
              },
              metadata_extractor: lambda {
                require_relative '../core/book_formats/rtf/rtf_metadata_extractor'
                Shoko::Core::BookFormats::Rtf::RtfMetadataExtractor
              },
              content_parser_factory: lambda { |raw, logger: nil|
                require_relative '../core/book_formats/rtf/rtf_content_parser'
                Shoko::Core::BookFormats::Rtf::RtfContentParser.new(raw, logger: logger)
              }
            )
          end
          private_class_method :register_rtf
        end
      end
end
