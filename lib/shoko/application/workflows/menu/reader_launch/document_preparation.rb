# frozen_string_literal: true

require_relative 'contracts'

module Shoko
  module Application
    module Workflows
      module Menu
        module ReaderLaunch
          # Handles document loading, worker warmup, and session document state.
          class DocumentPreparation
            include Contracts::DocumentPreparation

            Dependencies = Data.define(
              :document_service_factory,
              :reader_session_context,
              :state_writer,
              :background_worker_factory,
              :logger
            ) do
              def validate!
                missing = []
                missing << :reader_session_context if reader_session_context.nil?
                missing << :state_writer if state_writer.nil?
                return self if missing.empty?

                raise ArgumentError, "Missing document preparation dependencies: #{missing.join(', ')}"
              end
            end

            def initialize(deps:)
              dependencies = deps.validate!
              @document_service_factory = dependencies.document_service_factory
              @reader_session_context = dependencies.reader_session_context
              @state_writer = dependencies.state_writer
              @background_worker_factory = dependencies.background_worker_factory
              @logger = dependencies.logger
            end

            def document
              @reader_session_context&.document
            end

            def current_background_worker
              @reader_session_context&.background_worker
            end

            def ensure_background_worker(name:)
              return if current_background_worker

              worker = build_background_worker(name: name)
              @reader_session_context.background_worker = worker if worker
            # resilient-boundary
            rescue StandardError => e
              @logger&.debug('menu.document_preparation.ensure_background_worker_failed',
                             error: e.class.name, message: e.message)
              nil
            end

            def register_document(document)
              @reader_session_context.document = document
            end

            def clear_document!
              @reader_session_context.document = nil
            end

            def update_total_chapters(document)
              total = document&.chapter_count || 0
              @state_writer.update_pagination_state(total_chapters: total)
            end

            def load_document_for(path, progress_reporter:, path_resolution:)
              resolved_path = resolve_source_path(path, path_resolution)
              raise 'document_service_factory not available' unless @document_service_factory

              @document_service_factory.call(
                resolved_path,
                progress_reporter: progress_reporter,
                background_worker: current_background_worker
              ).load_document
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
            rescue StandardError => e
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
              factory = @background_worker_factory
              return nil unless factory

              factory.call(logger: @logger, name: name)
            rescue ArgumentError
              factory.call(name: name)
            # resilient-boundary
            rescue StandardError => e
              @logger&.debug('menu.document_preparation.build_background_worker_failed',
                             error: e.class.name, message: e.message)
              nil
            end
          end
        end
      end
    end
  end
end
