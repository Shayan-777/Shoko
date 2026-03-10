# frozen_string_literal: true

require_relative 'contracts'
require_relative '../../../../core/ports/outbound/document_loader'
require_relative '../../../../core/ports/outbound/background_worker_builder'
require_relative '../../../../core/ports/outbound/reader_launch_state'
require_relative '../../../../core/ports/outbound/reader_session_store'

module Shoko
  module Application
    module Workflows
      module Menu
        module ReaderLaunch
          # Handles document loading, worker warmup, and session document state.
          class DocumentPreparation
            include Contracts::DocumentPreparation

            Dependencies = Data.define(
              :document_loader,
              :reader_launch_state,
              :reader_session_store,
              :background_worker_builder,
              :logger
            ) do
              def validate!
                missing = []
                missing << :document_loader if document_loader.nil?
                missing << :reader_launch_state if reader_launch_state.nil?
                missing << :reader_session_store if reader_session_store.nil?
                missing << :background_worker_builder if background_worker_builder.nil?
                unless missing.empty?
                  raise ArgumentError, "Missing document preparation dependencies: #{missing.join(', ')}"
                end

                unless document_loader.is_a?(Shoko::Core::Ports::Outbound::DocumentLoader)
                  raise ArgumentError, 'document_loader must implement Core::Ports::Outbound::DocumentLoader'
                end
                unless background_worker_builder.is_a?(Shoko::Core::Ports::Outbound::BackgroundWorkerBuilder)
                  raise ArgumentError, 'background_worker_builder must implement Core::Ports::Outbound::BackgroundWorkerBuilder'
                end
                unless reader_launch_state.is_a?(Shoko::Core::Ports::Outbound::ReaderLaunchState)
                  raise ArgumentError, 'reader_launch_state must implement Core::Ports::Outbound::ReaderLaunchState'
                end
                unless reader_session_store.is_a?(Shoko::Core::Ports::Outbound::ReaderSessionStore)
                  raise ArgumentError, 'reader_session_store must implement Core::Ports::Outbound::ReaderSessionStore'
                end

                self
              end
            end

            def initialize(deps:)
              dependencies = deps.validate!
              @document_loader = dependencies.document_loader
              @reader_launch_state = dependencies.reader_launch_state
              @reader_session_store = dependencies.reader_session_store
              @background_worker_builder = dependencies.background_worker_builder
              @logger = dependencies.logger
            end

            def document
              @reader_launch_state.preloaded_document
            end

            def current_background_worker
              @reader_launch_state.background_worker
            end

            def ensure_background_worker(name:)
              return if current_background_worker

              worker = build_background_worker(name: name)
              @reader_launch_state.set_background_worker(worker)
            # resilient-boundary
            rescue Shoko::Error => e
              @logger&.debug('menu.document_preparation.ensure_background_worker_failed',
                             error: e.class.name, message: e.message)
              raise Shoko::StateUpdateError, "Failed to initialize reader background worker: #{e.message}"
            end

            def register_document(document)
              @reader_launch_state.set_preloaded_document(document)
            end

            def clear_document!
              @reader_launch_state.clear_preloaded_document
            end

            def update_total_chapters(document)
              total = document&.chapter_count || 0
              @reader_session_store.save(@reader_session_store.load.with(total_chapters: total))
            end

            def load_document_for(path, progress_reporter:, path_resolution:)
              resolved_path = resolve_source_path(path, path_resolution)
              @document_loader.load(
                path: resolved_path,
                progress_reporter: progress_reporter,
                background_worker: current_background_worker
              )
            end

            def ensure_reader_document_for(path:, path_resolution:, on_error:)
              target_path = path_resolution.canonical_path(path)
              existing = document
              return true if path_resolution.document_matches?(existing, target_path)

              loaded = load_document_for(target_path, progress_reporter: nil, path_resolution: path_resolution)
              register_document(loaded)
              update_total_chapters(loaded)
              true
            # resilient-boundary
            rescue Shoko::Error => e
              on_error&.call(path, e)
              false
            end

            private

            def resolve_source_path(path, path_resolution)
              return path unless path_resolution.cache_pointer?(path)

              payload = path_resolution.cache_payload(path, strict: false)
              resolved = payload&.source_path
              resolved && !resolved.to_s.empty? ? resolved : path
            end

            def build_background_worker(name:)
              @background_worker_builder.build(logger: @logger, name: name)
            # resilient-boundary
            rescue Shoko::Error => e
              @logger&.debug('menu.document_preparation.build_background_worker_failed',
                             error: e.class.name, message: e.message)
              raise Shoko::StateUpdateError, "Unable to build reader background worker: #{e.message}"
            end
          end
        end
      end
    end
  end
end
