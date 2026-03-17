# frozen_string_literal: true

require_relative '../../../core/ports/outbound/app_config_store'
require_relative '../../../core/ports/outbound/reader_session_store'
require_relative '../../../core/ports/outbound/reader_runtime_context'

module Shoko
  module Application
    module Workflows
      module Cli
        # Warms persisted reader-ready pagination so imported books can open
        # immediately in the subsequent menu session.
        class FolderImportReadinessWarmup
          Dependencies = Data.define(
            :page_calculator,
            :app_config_store,
            :reader_session_store,
            :reader_runtime_context,
            :logger
          ) do
            def validate!
              missing = []
              missing << :page_calculator if page_calculator.nil?
              missing << :app_config_store if app_config_store.nil?
              missing << :reader_session_store if reader_session_store.nil?
              missing << :reader_runtime_context if reader_runtime_context.nil?
              return self if missing.empty?

              raise ArgumentError, "Missing folder import warmup dependencies: #{missing.join(', ')}"
            end
          end

          DEFAULT_WIDTH = 80
          DEFAULT_HEIGHT = 24

          def initialize(deps:)
            dependencies = deps.validate!
            @page_calculator = dependencies.page_calculator
            @app_config_store = dependencies.app_config_store
            @reader_session_store = dependencies.reader_session_store
            @reader_runtime_context = dependencies.reader_runtime_context
            @logger = dependencies.logger
          end

          def warm(document)
            return :skipped unless warmable?(document)

            warm_dynamic_document(document)
          rescue Shoko::Error => e
            log_failure(error: e, document: document)
            :error
          ensure
            @page_calculator.reset_session!
          end

          private

          def warmable?(document)
            document && dynamic_mode?
          end

          def warm_dynamic_document(document)
            width, height = terminal_dimensions

            @page_calculator.reset_session!
            @page_calculator.build_dynamic_map!(
              width,
              height,
              document,
              config_reader: current_config,
              sidebar_visible: current_reader.sidebar_visible?
            )
            :warmed
          end

          def dynamic_mode?
            current_config.page_numbering_mode == :dynamic
          end

          def current_config
            @app_config_store.load
          end

          def current_reader
            @reader_session_store.load
          end

          def terminal_dimensions
            size = @reader_runtime_context.terminal_size
            width = size&.width.to_i
            height = size&.height.to_i
            width = DEFAULT_WIDTH if width <= 0
            height = DEFAULT_HEIGHT if height <= 0
            [width, height]
          end

          def canonical_path_for(document)
            document&.canonical_path
          end

          def log_failure(error:, document:)
            @logger&.debug(
              'cli.folder_import_readiness_warmup.failed',
              error: error.class.name,
              message: error.message,
              path: canonical_path_for(document)
            )
          end
        end
      end
    end
  end
end
