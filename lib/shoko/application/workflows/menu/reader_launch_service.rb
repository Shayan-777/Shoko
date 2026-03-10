# frozen_string_literal: true

require_relative '../../../core/ports/outbound/menu_book_selection'
require_relative '../../../core/models/menu_book'
require_relative 'reader_launch/contracts'
require_relative 'reader_launch/path_resolution'
require_relative 'reader_launch/document_preparation'
require_relative 'reader_launch/runtime_execution'
require_relative 'reader_launch/progress_orchestration'

module Shoko
  module Application
    module Workflows
      module Menu
        class ReaderLaunchService
          Dependencies = Data.define(
            :book_selection,
            :path_resolution,
            :document_preparation,
            :runtime_execution,
            :progress_orchestration
          ) do
            REQUIRED_FIELDS = %i[
              book_selection
              path_resolution
              document_preparation
              runtime_execution
              progress_orchestration
            ].freeze

            def validate!
              values = to_h
              missing = REQUIRED_FIELDS.select { |field| values[field].nil? }
              unless missing.empty?
                raise ArgumentError, "Missing required reader launch dependencies: #{missing.join(', ')}"
              end

              unless book_selection.is_a?(Shoko::Core::Ports::Outbound::MenuBookSelection)
                raise ArgumentError, 'book_selection must implement Core::Ports::Outbound::MenuBookSelection'
              end
              unless path_resolution.is_a?(Shoko::Application::Workflows::Menu::ReaderLaunch::Contracts::PathResolution)
                raise ArgumentError, 'path_resolution must implement ReaderLaunch::Contracts::PathResolution'
              end
              unless document_preparation.is_a?(Shoko::Application::Workflows::Menu::ReaderLaunch::Contracts::DocumentPreparation)
                raise ArgumentError, 'document_preparation must implement ReaderLaunch::Contracts::DocumentPreparation'
              end
              unless runtime_execution.is_a?(Shoko::Application::Workflows::Menu::ReaderLaunch::Contracts::RuntimeExecution)
                raise ArgumentError, 'runtime_execution must implement ReaderLaunch::Contracts::RuntimeExecution'
              end
              unless progress_orchestration.is_a?(Shoko::Application::Workflows::Menu::ReaderLaunch::Contracts::ProgressOrchestration)
                raise ArgumentError, 'progress_orchestration must implement ReaderLaunch::Contracts::ProgressOrchestration'
              end

              self
            end
          end

          def initialize(deps:)
            deps.validate!
            @book_selection = deps.book_selection
            @path_resolution = deps.path_resolution
            @document_preparation = deps.document_preparation
            @runtime_execution = deps.runtime_execution
            @progress_orchestration = deps.progress_orchestration
          end

          def open_selected_book
            book = @book_selection.selected_book

            return unless book
            unless book.is_a?(Shoko::Core::Models::MenuBook)
              raise ArgumentError, "book_selection must return Core::Models::MenuBook, got #{book.class}"
            end

            path = book.path
            if path && @path_resolution.file_exists?(path)
              load_and_open_with_progress(path)
            else
              file_not_found
            end
          end

          def open_book(path)
            return file_not_found unless @path_resolution.file_exists?(path)

            load_and_open_with_progress(path)
          # resilient-boundary
          rescue Shoko::Error => e
            handle_reader_error(path, e)
            raise
          end

          def run_reader(path)
            @runtime_execution.run_reader(
              path: path,
              ensure_reader_document_for: ->(candidate_path) { ensure_reader_document_for(candidate_path) }
            )
          end

          def load_and_open_with_progress(path)
            @progress_orchestration.load_and_open_with_progress(
              path: path,
              prepare_reader_launch: method(:prepare_reader_launch),
              run_reader: method(:run_reader)
            )
          # resilient-boundary
          rescue Shoko::Error => e
            handle_reader_error(path, e)
            raise
          end

          def file_not_found
            @runtime_execution.file_not_found
          end

          def handle_reader_error(path, error)
            @runtime_execution.handle_reader_error(path, error)
          end

          def valid_cache_path?(path)
            @path_resolution.valid_cache_path?(path)
          end

          def ensure_reader_document_for(path)
            @document_preparation.ensure_reader_document_for(
              path: path,
              path_resolution: @path_resolution,
              on_error: method(:handle_reader_error)
            )
          end

          private

          def prepare_reader_launch(path, presenter)
            @document_preparation.ensure_background_worker(name: 'document-preload')
            @progress_orchestration.prepare_reader_launch(
              path: path,
              load_document: lambda do |load_path, progress_reporter|
                @document_preparation.load_document_for(
                  load_path,
                  progress_reporter: progress_reporter,
                  path_resolution: @path_resolution
                )
              end,
              register_document: ->(document) { @document_preparation.register_document(document) },
              update_total_chapters: ->(document) { @document_preparation.update_total_chapters(document) },
              presenter: presenter
            )
          end
        end
      end
    end
  end
end
