# frozen_string_literal: true

module Shoko
  module Application
    module Workflows
      module Menu
        module ReaderLaunch
          # Executes menu->reader transition and lifecycle state updates.
          class RuntimeExecution
            Dependencies = Data.define(
              :menu_state_reader,
              :state_writer,
              :reader_state_reader,
              :reader_session_context,
              :menu_session_context,
              :recent_files_repository,
              :catalog,
              :menu_runtime,
              :path_resolution,
              :logger
            ) do
              def validate!
                missing = %i[
                  menu_state_reader
                  state_writer
                  reader_state_reader
                  reader_session_context
                  menu_session_context
                  catalog
                  menu_runtime
                  path_resolution
                ].select { |field| public_send(field).nil? }
                return self if missing.empty?

                raise ArgumentError, "Missing runtime execution dependencies: #{missing.join(', ')}"
              end
            end

            def initialize(deps:)
              dependencies = deps.validate!
              @menu_state_reader = dependencies.menu_state_reader
              @state_writer = dependencies.state_writer
              @reader_state_reader = dependencies.reader_state_reader
              @reader_session_context = dependencies.reader_session_context
              @menu_session_context = dependencies.menu_session_context
              @recent_files_repository = dependencies.recent_files_repository
              @catalog = dependencies.catalog
              @menu_runtime = dependencies.menu_runtime
              @path_resolution = dependencies.path_resolution
              @logger = dependencies.logger
            end

            def run_reader(path:, ensure_reader_document_for:)
              prior_mode = @menu_state_reader.current_menu_mode
              reader_path = @path_resolution.canonical_path(path)

              return unless ensure_reader_document_for.call(reader_path)

              recent_path = @path_resolution.canonical_recent_path(reader_path)
              @recent_files_repository&.add(recent_path) if recent_path

              @logger&.debug('menu.run_reader.dispatch_running', path: reader_path, running: true)
              @state_writer.update_reader_meta(book_path: reader_path, running: true)
              @state_writer.update_reader(mode: :read)

              running_after = @reader_state_reader.running?
              @logger&.debug('menu.run_reader.after_dispatch', running_value: running_after)

              @menu_session_context.last_opened_path = reader_path
              @menu_runtime.run_reader(
                path: reader_path,
                preloaded_document: @reader_session_context.document,
                background_worker: @reader_session_context.background_worker
              )
            # resilient-boundary
            rescue StandardError => e
              @logger&.error('menu.run_reader.exception', error: e.class.name, message: e.message)
              raise
            ensure
              @logger&.debug('menu.run_reader.ensure', prior_mode: prior_mode)
              @reader_session_context.document = nil
              @menu_runtime.switch_mode(prior_mode || :browse)
            end

            def file_not_found
              @catalog.update_scan_state(status: :error, message: 'File not found')
            end

            def handle_reader_error(path, error)
              @logger&.error('Failed to open book', error: error.message, path: path)
              @catalog.update_scan_state(
                status: :error,
                message: "Failed: #{error.class}: #{error.message[0, 60]}"
              )

              return unless @logger.respond_to?(:debug)

              @logger&.debug(
                'Reader error backtrace',
                path: path,
                backtrace: Array(error.backtrace).join("\n")
              )
            end
          end
        end
      end
    end
  end
end
