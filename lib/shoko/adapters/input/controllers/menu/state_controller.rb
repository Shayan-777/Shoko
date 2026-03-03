# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Coordinates menu workflows via precomposed collaborators.
          class StateController
            Dependencies = Data.define(
              :menu_state_reader,
              :menu_state_writer,
              :reader_launch_service,
              :download_workflow,
              :dictionary_workflow,
              :annotation_workflow,
              :catalog,
              :logger
            ) do
              REQUIRED_FIELDS = %i[
                menu_state_reader
                menu_state_writer
                reader_launch_service
                download_workflow
                dictionary_workflow
                annotation_workflow
                catalog
              ].freeze

              def validate!
                values = to_h
                missing = REQUIRED_FIELDS.select { |field| values[field].nil? }
                return self if missing.empty?

                raise ArgumentError, "Missing required menu state controller dependencies: #{missing.join(', ')}"
              end
            end

            def initialize(menu:, deps:)
              raise ArgumentError, 'menu is required' if menu.nil?
              raise ArgumentError, 'deps is required' if deps.nil?

              dependencies = deps.validate!
              @menu = menu
              @menu_state_reader = dependencies.menu_state_reader
              @menu_state_writer = dependencies.menu_state_writer
              @reader_launch_service = dependencies.reader_launch_service
              @download_workflow = dependencies.download_workflow
              @dictionary_workflow = dependencies.dictionary_workflow
              @annotation_workflow = dependencies.annotation_workflow
              @catalog = dependencies.catalog
              @logger = dependencies.logger
            end

            def open_selected_book
              @reader_launch_service.open_selected_book
            end

            def open_book(path)
              @reader_launch_service.open_book(path)
            end

            def run_reader(path)
              @reader_launch_service.run_reader(path)
            end

            def load_and_open_with_progress(path)
              @reader_launch_service.load_and_open_with_progress(path)
            end

            def file_not_found
              @reader_launch_service.file_not_found
            end

            def handle_reader_error(path, error)
              @reader_launch_service.handle_reader_error(path, error)
            end

            def valid_cache_path?(path)
              @reader_launch_service.valid_cache_path?(path)
            end

            def refresh_scan(force: false)
              @catalog.start_scan(force: force)
            end

            def search_downloads(query:, page_url: nil)
              @download_workflow.search_downloads(query: query, page_url: page_url)
            end

            def download_book(book)
              @download_workflow.download_book(book)
            end

            def fetch_dictionary_catalog
              @dictionary_workflow.fetch_dictionary_catalog
            end

            def download_dictionary(entry)
              @dictionary_workflow.download_dictionary(entry)
            end

            def open_selected_annotation
              @annotation_workflow.open_selected_annotation
            end

            def open_selected_annotation_for_edit
              @annotation_workflow.open_selected_annotation_for_edit
            end

            def delete_selected_annotation
              @annotation_workflow.delete_selected_annotation
            end

            def save_current_annotation_edit
              @annotation_workflow.save_current_annotation_edit
            end
          end
        end
      end
    end
  end
end
