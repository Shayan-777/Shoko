# frozen_string_literal: true

module Shoko
  module Bootstrap
    module ContainerFactory
      module DomainApplicationRegistration
        # Document loader and parser resolver registration.
        module DocumentLoaderServices
          # Build a lambda that resolves the correct content parser for a chapter
          # based on its metadata[:format] hint. Falls back to the XHTML parser.
          def build_format_parser_resolver(xhtml_factory, logger)
            lambda do |raw, chapter|
              metadata = chapter&.metadata
              format = (metadata[:format] || metadata['format'] if metadata.is_a?(Hash))

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
              Shoko::Adapters::BookSources::DocumentLoaderAdapter.new(
                wrapping_service: c.resolve(:wrapping_service),
                formatting_service: c.resolve(:formatting_service),
                reader_launch_state: c.resolve(:reader_launch_state),
                instrumentation: c.resolve(:instrumentation_service),
                runtime_config: c.resolve(:runtime_config),
                logger: c.resolve(:logger),
                book_cache_pipeline_factory: c.resolve(:book_cache_pipeline_factory)
              )
            end
          end
        end
      end
    end
  end
end
