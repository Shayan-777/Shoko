# frozen_string_literal: true

require_relative '../../../shared/hash_normalizer'

module Shoko
  module Composition
    module ContainerFactory
      module DomainApplicationRegistration
        # Document loader and parser resolver registration.
        module DocumentLoaderServices
          # Build a lambda that resolves the correct content parser for a chapter
          # based on its metadata[:format] hint. Falls back to the XHTML parser.
          def build_format_parser_resolver(xhtml_factory, logger)
            lambda do |raw, chapter|
              metadata = Shoko::Shared::HashNormalizer.symbolize_keys(chapter&.metadata) || {}
              format = metadata[:format]

              format_key = format.to_s.strip.downcase
              if !format_key.empty? && format_key != 'epub'
                factory = Shoko::Adapters::BookSources::FormatRegistry.content_parser_factory_for("dummy.#{format_key}")
                parser = factory&.call(raw, logger: logger)
                return parser if parser
              end

              xhtml_factory.call(raw)
            end
          end

          def register_document_loader(container)
            container.register_singleton(:document_loader) do |c|
              require_relative '../../../application/services/book_document_loader'

              Shoko::Application::Services::BookDocumentLoader.new(
                book_cache_store: c.resolve(:book_cache_store),
                book_importer_resolver: c.resolve(:book_importer_resolver),
                book_resource_warmup: c.resolve(:image_cache_warmup),
                runtime_config: c.resolve(:runtime_config),
                logger: c.resolve(:logger)
              )
            end
          end
        end
      end
    end
  end
end
