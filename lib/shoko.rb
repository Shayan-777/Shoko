# frozen_string_literal: true

# Shoko - A fast, keyboard-driven terminal ebook reader
#
# This is the main entry point for the Shoko gem.

module Shoko
  module Adapters
    module Output
      module Ui; end
      module Rendering; end
    end

    module Input; end

    module Storage
      module Repositories; end
    end

    module Monitoring; end

    module BookSources
      autoload :GutendexClient, 'shoko/adapters/book_sources/gutendex_client'

      module Epub
        autoload :EpubImporter, 'shoko/adapters/book_sources/epub/epub_importer'
        autoload :EpubResourceLoader, 'shoko/adapters/book_sources/epub/epub_resource_loader'
      end
      module Fb2
        autoload :Fb2Importer, 'shoko/adapters/book_sources/fb2/fb2_importer'
      end
      module Pdf
        autoload :PdfImporter, 'shoko/adapters/book_sources/pdf/pdf_importer'
      end
      module Kindle
        autoload :KindleImporter, 'shoko/adapters/book_sources/kindle/kindle_importer'
      end
      module Rtf
        autoload :RtfImporter, 'shoko/adapters/book_sources/rtf/rtf_importer'
      end
    end

    module State
      module Actions; end
      module Selectors; end
    end
  end

  module Core
    module Services
      module Pagination; end
    end

    module Models; end
    module Events; end

    module BookFormats
      module Epub
        module OPF; end
        autoload :XHTMLContentParser, 'shoko/core/book_formats/epub/xhtml_content_parser'
        autoload :MetadataExtractor, 'shoko/core/book_formats/epub/metadata_extractor'
      end
      module Fb2
        autoload :Fb2ContentParser, 'shoko/core/book_formats/fb2/fb2_content_parser'
        autoload :Fb2MetadataExtractor, 'shoko/core/book_formats/fb2/fb2_metadata_extractor'
      end
      module Pdf
        autoload :PdfReader, 'shoko/core/book_formats/pdf/pdf_reader'
        autoload :PdfTextExtractor, 'shoko/core/book_formats/pdf/pdf_text_extractor'
        autoload :PdfMetadataExtractor, 'shoko/core/book_formats/pdf/pdf_metadata_extractor'
        autoload :PdfContentParser, 'shoko/core/book_formats/pdf/pdf_content_parser'
      end
      module Kindle
        autoload :PdbHeaderParser, 'shoko/core/book_formats/kindle/pdb_header_parser'
        autoload :MobiHeaderParser, 'shoko/core/book_formats/kindle/mobi_header_parser'
        autoload :ExthParser, 'shoko/core/book_formats/kindle/exth_parser'
        autoload :PalmdocDecompressor, 'shoko/core/book_formats/kindle/palmdoc_decompressor'
        autoload :KindleMetadataExtractor, 'shoko/core/book_formats/kindle/kindle_metadata_extractor'
        autoload :KindleContentParser, 'shoko/core/book_formats/kindle/kindle_content_parser'
      end
      module Rtf
        autoload :RtfParser, 'shoko/core/book_formats/rtf/rtf_parser'
        autoload :RtfMetadataExtractor, 'shoko/core/book_formats/rtf/rtf_metadata_extractor'
        autoload :RtfContentParser, 'shoko/core/book_formats/rtf/rtf_content_parser'
      end
    end
  end

  module Application
    module Controllers; end
    module UseCases; end
    module State; end
    module UI; end
  end
end

require_relative 'shoko/application/composition/bootstrap/runtime_bootstrap'
Shoko::Application::Composition::Bootstrap::RuntimeBootstrap.boot!
