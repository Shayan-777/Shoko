# frozen_string_literal: true

require_relative '../../application/ports/outbound/book_importer_resolver'
require_relative '../../shared/errors'
require_relative 'format_registry'

module Shoko
  module Adapters
    module BookSources
      # Book-source adapter that resolves and runs format importers.
      #
      # Every registered importer shares the uniform construction contract
      # `new(progress_reporter:, runtime_config:)` (mirroring the registry's
      # content-parser factory contract), so importers are constructed
      # directly — no signature probing.
      class BookImporterResolverAdapter
        include Shoko::Application::Ports::Outbound::BookImporterResolver

        def initialize(format_registry: FormatRegistry)
          @format_registry = format_registry
        end

        def import(path, progress_reporter: nil, runtime_config: nil)
          importer_class = @format_registry.importer_for(path)
          raise Shoko::BookParseError.new("unsupported book format: #{path}", path) unless importer_class

          importer = importer_class.new(progress_reporter: progress_reporter, runtime_config: runtime_config)
          importer.import(path)
        end
      end
    end
  end
end
