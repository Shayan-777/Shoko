# frozen_string_literal: true

module Shoko
  module Application
    module Workflows
      module Menu
        module ReaderLaunch
          # Typed collaborator contracts for ReaderLaunchService orchestration.
          module Contracts
            module PathResolution
              def file_exists?(_path)
                raise NotImplementedError, "#{self.class} must implement #file_exists?"
              end

              def valid_cache_path?(_path)
                raise NotImplementedError, "#{self.class} must implement #valid_cache_path?"
              end
            end

            module DocumentPreparation
              def ensure_reader_document_for(path:, path_resolution:, on_error:)
                raise NotImplementedError, "#{self.class} must implement #ensure_reader_document_for"
              end

              def ensure_background_worker(name:)
                raise NotImplementedError, "#{self.class} must implement #ensure_background_worker"
              end

              def load_document_for(_path, progress_reporter:, path_resolution:)
                raise NotImplementedError, "#{self.class} must implement #load_document_for"
              end

              def register_document(_document)
                raise NotImplementedError, "#{self.class} must implement #register_document"
              end

              def update_total_chapters(_document)
                raise NotImplementedError, "#{self.class} must implement #update_total_chapters"
              end
            end

            module RuntimeExecution
              def run_reader(path:, ensure_reader_document_for:)
                raise NotImplementedError, "#{self.class} must implement #run_reader"
              end

              def file_not_found
                raise NotImplementedError, "#{self.class} must implement #file_not_found"
              end

              def handle_reader_error(_path, _error)
                raise NotImplementedError, "#{self.class} must implement #handle_reader_error"
              end
            end

            module ProgressOrchestration
              def load_and_open_with_progress(path:, prepare_reader_launch:, run_reader:)
                raise NotImplementedError, "#{self.class} must implement #load_and_open_with_progress"
              end

              def prepare_reader_launch(path:, load_document:, register_document:, update_total_chapters:, presenter:)
                raise NotImplementedError, "#{self.class} must implement #prepare_reader_launch"
              end
            end
          end
        end
      end
    end
  end
end
