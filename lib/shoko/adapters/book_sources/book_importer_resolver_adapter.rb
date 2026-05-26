# frozen_string_literal: true

require_relative '../../application/ports/outbound/book_importer_resolver'
require_relative '../../shared/errors'
require_relative 'format_registry'

module Shoko
  module Adapters
    module BookSources
      # Book-source adapter that resolves and runs format importers.
      class BookImporterResolverAdapter
        include Shoko::Application::Ports::Outbound::BookImporterResolver

        KEYWORD_PARAMETER_KINDS = %i[key keyreq keyrest].freeze

        def initialize(format_registry: FormatRegistry)
          @format_registry = format_registry
        end

        def import(path, progress_reporter: nil, runtime_config: nil, logger: nil)
          importer_class = @format_registry.importer_for(path)
          raise Shoko::BookParseError.new("unsupported book format: #{path}", path) unless importer_class

          importer = importer_class.new(**importer_kwargs(importer_class, progress_reporter, runtime_config, logger))
          importer.import(path)
        end

        private

        def importer_kwargs(importer_class, progress_reporter, runtime_config, logger)
          kwargs = {}
          kwargs[:progress_reporter] = progress_reporter if supports_keyword?(importer_class, :progress_reporter)
          kwargs[:runtime_config] = runtime_config if supports_keyword?(importer_class, :runtime_config)
          kwargs[:logger] = logger if supports_keyword?(importer_class, :logger)
          kwargs
        end

        def supports_keyword?(klass, keyword)
          klass.instance_method(:initialize).parameters.any? do |kind, name|
            KEYWORD_PARAMETER_KINDS.include?(kind) && (name == keyword || kind == :keyrest)
          end
        end
      end
    end
  end
end
