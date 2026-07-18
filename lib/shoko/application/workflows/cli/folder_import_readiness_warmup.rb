# frozen_string_literal: true

require 'shoko/application/ports/outbound/app_config_store'
require 'shoko/application/ports/internal/document_warmup'
require 'shoko/application/ports/outbound/reader_view_state_store'
require 'shoko/application/ports/outbound/reader_runtime_context'
require 'shoko/core/services/progress_ratio'

module Shoko
  module Application
    module Workflows
      module Cli
        # Warms persisted reader-ready pagination so imported books can open
        # immediately in the subsequent menu session.
        class FolderImportReadinessWarmup
          include Shoko::Application::Ports::Internal::DocumentWarmup

          Dependencies = Data.define(
            :page_calculator,
            :app_config_store,
            :reader_view_state_store,
            :reader_runtime_context,
            :logger
          ) do
            def validate!
              missing = []
              missing << :page_calculator if page_calculator.nil?
              missing << :app_config_store if app_config_store.nil?
              missing << :reader_view_state_store if reader_view_state_store.nil?
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
            @reader_view_state_store = dependencies.reader_view_state_store
            @reader_runtime_context = dependencies.reader_runtime_context
            @logger = dependencies.logger
          end

          def warm(document, progress_reporter: nil)
            return :skipped unless warmable?(document)

            warm_dynamic_document(document, progress_reporter: progress_reporter)
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

          def warm_dynamic_document(document, progress_reporter:)
            width, height = terminal_dimensions

            @page_calculator.reset_session!
            progress_reporter&.update_status(message: 'Warming pagination cache...', progress: 0.0)
            @page_calculator.build_dynamic_map!(
              width,
              height,
              document,
              config_reader: current_config,
              &warmup_progress_callback(progress_reporter)
            )
            progress_reporter&.update_status(message: 'Pagination cache warmed.', progress: 1.0)
            :warmed
          end

          def warmup_progress_message(done, total)
            total_i = total.to_i
            return 'Warming pagination cache...' unless total_i.positive?

            "Warming pagination cache (#{done.to_i}/#{total_i})..."
          end

          def warmup_progress_callback(progress_reporter)
            return nil unless progress_reporter

            lambda do |done, total|
              progress_reporter.update_status(
                message: warmup_progress_message(done, total),
                progress: Shoko::Core::Services::ProgressRatio.compute(done, total)
              )
            end
          end

          def dynamic_mode?
            current_config&.page_numbering_mode == :dynamic
          end

          def current_config
            @app_config_store.load
          end

          def current_view_state
            @reader_view_state_store.load
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
