# frozen_string_literal: true

require_relative 'contracts'
require_relative '../../../../application/ports/outbound/menu_session_store'
require_relative '../../../../application/ports/outbound/reader_session_store'

module Shoko
  module Application
    module Workflows
      module Menu
        module ReaderLaunch
          # Executes menu->reader transition and lifecycle state updates.
          class RuntimeExecution
            include Contracts::RuntimeExecution

            Dependencies = Data.define(
              :menu_session_store,
              :reader_session_store,
              :reader_launch_state,
              :menu_launch_state,
              :recent_files_repository,
              :catalog,
              :menu_runtime,
              :path_resolution,
              :logger
            ) do
              def validate!
                missing = required_fields.select { |field| to_h[field].nil? }
                unless missing.empty?
                  raise ArgumentError, "Missing runtime execution dependencies: #{missing.join(', ')}"
                end

                validate_session_store_contracts!

                self
              end

              def required_fields
                %i[
                  menu_session_store
                  reader_session_store
                  reader_launch_state
                  menu_launch_state
                  catalog
                  menu_runtime
                  path_resolution
                ]
              end

              def validate_session_store_contracts!
                validate_contract(menu_session_store,
                                  Shoko::Application::Ports::Outbound::MenuSessionStore,
                                  'menu_session_store must implement Application::Ports::Outbound::MenuSessionStore')
                validate_contract(reader_session_store,
                                  Shoko::Application::Ports::Outbound::ReaderSessionStore,
                                  'reader_session_store must implement Application::Ports::Outbound::ReaderSessionStore')
              end

              def validate_contract(value, contract, message)
                raise ArgumentError, message unless value.is_a?(contract)
              end
            end

            def initialize(deps:)
              dependencies = deps.validate!
              @menu_session_store = dependencies.menu_session_store
              @reader_session_store = dependencies.reader_session_store
              @reader_launch_state = dependencies.reader_launch_state
              @menu_launch_state = dependencies.menu_launch_state
              @recent_files_repository = dependencies.recent_files_repository
              @catalog = dependencies.catalog
              @menu_runtime = dependencies.menu_runtime
              @path_resolution = dependencies.path_resolution
              @logger = dependencies.logger
            end

            def run_reader(path:, ensure_reader_document_for:)
              prior_mode = @menu_session_store.load.mode
              reader_path = @path_resolution.canonical_path(path)

              return unless ensure_reader_document_for.call(reader_path)

              remember_recent_path(reader_path)
              mark_reader_running(reader_path)
              launch_reader_runtime(reader_path)
            rescue StandardError => e
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
              @catalog.update_scan_state(status: :error, message: "Failed: #{error.class}: #{error.message[0, 60]}")

              @logger&.debug(
                'Reader error backtrace',
                path: path,
                backtrace: Array(error.backtrace).join("\n")
              )
            end

            private

            def remember_recent_path(reader_path)
              recent_path = @path_resolution.canonical_recent_path(reader_path)
              @recent_files_repository&.add(recent_path) if recent_path
            end

            def mark_reader_running(reader_path)
              @logger&.debug('menu.run_reader.dispatch_running', path: reader_path, running: true)
              snapshot = @reader_session_store.load.with(book_path: reader_path, running: true, mode: :read)
              @reader_session_store.save(snapshot)
            end

            def launch_reader_runtime(reader_path)
              @menu_launch_state.last_opened_path = reader_path
              @menu_runtime.run_reader(
                path: reader_path,
                preloaded_document: @reader_launch_state.preloaded_document,
                background_worker: @reader_launch_state.background_worker
              )
            end
          end
        end
      end
    end
  end
end
