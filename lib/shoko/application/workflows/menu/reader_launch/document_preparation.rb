# frozen_string_literal: true

require_relative 'contracts'
require 'shoko/application/ports/outbound/document_loader'
require 'shoko/application/ports/outbound/background_worker_builder'
require 'shoko/application/ports/outbound/reader_launch_state'
require 'shoko/application/ports/outbound/reader_session_store'

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
                missing = missing_dependencies
                raise_missing_dependencies!(missing) if missing.any?

                validate_contracts!
                self
              end

              def missing_dependencies
                [].tap do |missing|
                  missing << :document_loader if document_loader.nil?
                  missing << :reader_launch_state if reader_launch_state.nil?
                  missing << :reader_session_store if reader_session_store.nil?
                  missing << :background_worker_builder if background_worker_builder.nil?
                end
              end

              def validate_contracts!
                validate_contract(document_loader,
                                  Shoko::Application::Ports::Outbound::DocumentLoader,
                                  'document_loader must implement Application::Ports::Outbound::DocumentLoader')
                validate_contract(background_worker_builder,
                                  Shoko::Application::Ports::Outbound::BackgroundWorkerBuilder,
                                  'background_worker_builder must implement Application::Ports::Outbound::BackgroundWorkerBuilder')
                validate_contract(reader_launch_state,
                                  Shoko::Application::Ports::Outbound::ReaderLaunchState,
                                  'reader_launch_state must implement Application::Ports::Outbound::ReaderLaunchState')
                validate_contract(reader_session_store,
                                  Shoko::Application::Ports::Outbound::ReaderSessionStore,
                                  'reader_session_store must implement Application::Ports::Outbound::ReaderSessionStore')
              end

              def validate_contract(value, contract, message)
                raise ArgumentError, message unless value.is_a?(contract)
              end

              def raise_missing_dependencies!(missing)
                raise ArgumentError, "Missing document preparation dependencies: #{missing.join(', ')}"
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
              @reader_launch_state.background_worker = worker
            rescue StandardError => e
              @logger&.debug('menu.document_preparation.ensure_background_worker_failed',
                             error: e.class.name,
                             message: e.message)
              raise Shoko::StateUpdateError, "Failed to initialize reader background worker: #{e.message}"
            end

            def register_document(document)
              @reader_launch_state.preloaded_document = document
            end

            def clear_document!
              @reader_launch_state.clear_preloaded_document
            end

            def update_total_chapters(document)
              total = document&.chapter_count || 0
              snapshot = @reader_session_store.load
              # This runs only when switching to a *different* document, so a
              # current_chapter left over from the previously open book can exceed
              # the new book's chapter count (tripping the current_chapter <=
              # total_chapters invariant). Reset out-of-range positions to the
              # start; the new book's saved progress is restored right afterward.
              @reader_session_store.save(
                snapshot.with(total_chapters: total, current_chapter: in_range_chapter(snapshot.current_chapter, total))
              )
            end

            def in_range_chapter(current, total)
              current_index = current.to_i
              return current_index if total.to_i.positive? && current_index < total.to_i

              0
            end

            def load_document_for(path, progress_reporter:, path_resolution:)
              resolved_path = resolve_source_path(path, path_resolution)
              @document_loader.load(
                path: resolved_path,
                progress_reporter: progress_reporter
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
            rescue StandardError => e
              handle_document_load_error(path, e, on_error)
              false
            end

            private

            def resolve_source_path(path, path_resolution)
              return path unless path_resolution.cache_pointer?(path)

              payload = path_resolution.cache_payload(path, strict: false)
              resolved = payload&.source_path
              resolved && !resolved.to_s.empty? ? resolved : path
            end

            # Opening a book is an isolation boundary: a book that fails to
            # load — malformed input or a parser bug alike — must surface as a
            # menu error message, never crash the application.
            def handle_document_load_error(path, error, on_error)
              on_error&.call(path, error)
            end

            def build_background_worker(name:)
              @background_worker_builder.build(logger: @logger, name: name)
            rescue StandardError => e
              @logger&.debug('menu.document_preparation.build_background_worker_failed',
                             error: e.class.name,
                             message: e.message)
              raise Shoko::StateUpdateError, "Unable to build reader background worker: #{e.message}"
            end
          end
        end
      end
    end
  end
end
