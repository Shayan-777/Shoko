# frozen_string_literal: true

require_relative 'contracts'

module Shoko
  module Application
    module Workflows
      module Menu
        module ReaderLaunch
          # Executes menu->reader transition and lifecycle state updates.
          class RuntimeExecution
            include Contracts::RuntimeExecution

            Dependencies = Data.define(
              :menu_state_reader,
              :state_writer,
              :reader_launch_state,
              :menu_launch_state,
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
                  reader_launch_state
                  menu_launch_state
                  catalog
                  menu_runtime
                  path_resolution
                ].select { |field| to_h[field].nil? }
                return self if missing.empty?

                raise ArgumentError, "Missing runtime execution dependencies: #{missing.join(', ')}"
              end
            end

            def initialize(deps:)
              dependencies = deps.validate!
              @menu_state_reader = dependencies.menu_state_reader
              @state_writer = dependencies.state_writer
              @reader_launch_state = dependencies.reader_launch_state
              @menu_launch_state = dependencies.menu_launch_state
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

              @menu_launch_state.set_last_opened_path(reader_path)
              @menu_runtime.run_reader(
                path: reader_path,
                preloaded_document: @reader_launch_state.preloaded_document,
                background_worker: @reader_launch_state.background_worker
              )
            # resilient-boundary
            rescue Shoko::Error => e
              @logger&.error('menu.run_reader.exception', error: e.class.name, message: e.message)
              raise
            ensure
              @logger&.debug('menu.run_reader.ensure', prior_mode: prior_mode)
              @reader_launch_state.clear_preloaded_document
              @reader_launch_state.clear_background_worker
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
