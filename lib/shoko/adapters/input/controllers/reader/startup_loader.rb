# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Handles reader startup data loading and preloaded-document validation.
          class StartupLoader
            def initialize(path:, document_service_factory:, reader_session_context:, state_writer:, document_matches_path:,
                           logger: nil)
              @path = path
              @document_service_factory = document_service_factory
              @reader_session_context = reader_session_context
              @state_writer = state_writer
              @document_matches_path = document_matches_path
              @logger = logger
            end

            def validate_preloaded_document(existing, target_path)
              return nil unless existing

              return existing if @document_matches_path.call(existing, target_path)

              nil
            rescue StandardError
              nil
            end

            def load_document(current_doc:, on_loaded:)
              return current_doc if current_doc
              raise 'document_service_factory not available' unless @document_service_factory

              document_service = @document_service_factory.call(@path)
              doc = document_service.load_document
              @reader_session_context.document = doc if @reader_session_context
              begin
                @state_writer.update_pagination_state(total_chapters: doc&.chapter_count || 0)
              rescue StandardError
                nil
              end
              on_loaded.call(doc)
              doc
            end

            def load_saved_state(state_controller:)
              state_controller.load_progress
              state_controller.load_bookmarks
              state_controller.refresh_annotations
            end

            def apply_pending_jump(jump_handler:)
              jump_handler.apply
            rescue StandardError => e
              @logger&.debug('Pending jump apply failed', error: e.message)
            end
          end
        end
      end
    end
  end
end
