# frozen_string_literal: true

require 'shoko/application/pending_jump_handler'
require 'shoko/application/services/pagination/pagination_coordinator'
require 'shoko/application/ports/outbound/background_worker_builder'
require 'shoko/core/services/in_book_search_service'
require 'shoko/adapters/input/controllers/reader/lifecycle_runner'
require_relative 'resolved_dependencies'

module Shoko
  module Composition
    module ContainerFactory
      module ControllerComposition
        module ReaderBuilder
          # Builds runtime-only reader dependencies after the container graph is resolved.
          module RuntimePreparation
            OVERRIDDEN_FIELDS = %i[worker async_executor].freeze

            PreparedDependencies = Data.define(
              *ResolvedDependencies.members,
              :reader_lifecycle_factory,
              :pending_jump_handler_factory,
              :pagination_coordinator_factory,
              :in_book_search_service
            )

            module_function

            def prepare(resolved)
              prepared = build_prepared_dependencies(resolved)
              sync_reader_launch_state!(
                prepared.reader_launch_state,
                document: prepared.document,
                worker: prepared.worker
              )
              prepared
            end

            def build_prepared_dependencies(resolved)
              worker = resolved.worker || build_background_worker(
                background_worker_builder: resolved.background_worker_builder,
                logger: resolved.logger,
                name: 'reader-runtime'
              )

              PreparedDependencies.new(
                **resolved_attributes(resolved),
                **prepared_runtime_attributes(resolved, worker)
              )
            end
            private_class_method :build_prepared_dependencies

            def prepared_runtime_attributes(resolved, worker)
              {
                worker: worker,
                async_executor: prefer_worker_executor(async_executor: resolved.async_executor, worker: worker),
                reader_lifecycle_factory: reader_lifecycle_factory,
                pending_jump_handler_factory: pending_jump_handler_factory(resolved.reader_session_store),
                pagination_coordinator_factory: pagination_coordinator_factory,
                in_book_search_service: build_in_book_search_service(resolved),
              }
            end
            private_class_method :prepared_runtime_attributes

            def build_in_book_search_service(resolved)
              launch_state = resolved.reader_launch_state
              in_book_search_service(
                document: resolved.document,
                logger: resolved.logger,
                page_calculator: resolved.page_calculator,
                app_config_store: resolved.app_config_store,
                chapter_formatter: resolved.formatting_service,
                # Cached books load their document after this build (the
                # startup loader publishes it); bind late or search scans nil.
                document_provider: -> { launch_state&.preloaded_document }
              )
            end
            private_class_method :build_in_book_search_service

            def resolved_attributes(resolved)
              resolved.to_h.except(*OVERRIDDEN_FIELDS)
            end
            private_class_method :resolved_attributes

            def build_background_worker(background_worker_builder:, logger:, name:)
              return nil unless background_worker_builder

              unless background_worker_builder.is_a?(Shoko::Application::Ports::Outbound::BackgroundWorkerBuilder)
                raise ArgumentError,
                      'background_worker_builder must implement Application::Ports::Outbound::BackgroundWorkerBuilder'
              end

              background_worker_builder.build(logger: logger, name: name)
            end
            private_class_method :build_background_worker

            def prefer_worker_executor(async_executor:, worker:)
              return async_executor unless worker
              return worker if async_executor.nil?
              return worker if inline_executor?(async_executor)

              async_executor
            end
            private_class_method :prefer_worker_executor

            def inline_executor?(executor)
              return false unless executor
              return false unless defined?(Shoko::Adapters::Runtime::InlineExecutorAdapter)

              executor.is_a?(Shoko::Adapters::Runtime::InlineExecutorAdapter)
            end
            private_class_method :inline_executor?

            def reader_lifecycle_factory
              lambda do |controller, **kwargs|
                Shoko::Adapters::Input::Controllers::Reader::LifecycleRunner.new(controller, **kwargs)
              end
            end
            private_class_method :reader_lifecycle_factory

            def pending_jump_handler_factory(reader_session_store)
              lambda do |**kwargs|
                Shoko::Application::PendingJumpHandler.new(
                  reader_session_store: reader_session_store,
                  annotation_editor_launcher: kwargs[:annotation_editor_launcher],
                  navigation_service: kwargs[:navigation_service],
                  anchor_resolver: kwargs[:anchor_resolver]
                )
              end
            end
            private_class_method :pending_jump_handler_factory

            def pagination_coordinator_factory
              lambda do |**kwargs|
                Shoko::Application::Services::Pagination::PaginationCoordinator.new(**kwargs)
              end
            end
            private_class_method :pagination_coordinator_factory

            def in_book_search_service(document:, logger:, page_calculator:, app_config_store:, chapter_formatter:,
                                       document_provider: nil)
              Shoko::Core::Services::InBookSearchService.new(
                document: document,
                logger: logger,
                page_calculator: page_calculator,
                config_reader: app_config_store,
                chapter_formatter: chapter_formatter,
                document_provider: document_provider
              )
            end
            private_class_method :in_book_search_service

            def sync_reader_launch_state!(launch_state, document:, worker:)
              return unless launch_state

              launch_state.preloaded_document = document if document
              launch_state.background_worker = worker if worker
            end
            private_class_method :sync_reader_launch_state!
          end
        end
      end
    end
  end
end
