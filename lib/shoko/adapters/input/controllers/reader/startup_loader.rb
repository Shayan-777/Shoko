# frozen_string_literal: true

require_relative '../../../../core/ports/outbound/document_loader'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Handles reader startup data loading and preloaded-document validation.
          class StartupLoader
            def initialize(path:, document_loader:, reader_launch_state:, state_writer:, document_matches_path:,
                           logger: nil)
              @path = path
              unless document_loader.is_a?(Shoko::Core::Ports::Outbound::DocumentLoader)
                raise ArgumentError, 'document_loader must implement Core::Ports::Outbound::DocumentLoader'
              end
              @document_loader = document_loader
              @reader_launch_state = reader_launch_state
              @state_writer = state_writer
              @document_matches_path = document_matches_path
              @logger = logger
            end

            def validate_preloaded_document(existing, target_path)
              return nil unless existing

              return existing if @document_matches_path.call(existing, target_path)

              nil
            end

            def load_document(current_doc:, on_loaded:)
              return current_doc if current_doc

              doc = @document_loader.load(path: @path)
              @reader_launch_state.set_preloaded_document(doc) if @reader_launch_state
              @state_writer.update_pagination_state(total_chapters: doc&.chapter_count || 0)
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
            rescue Shoko::FatalExternalInputError
              raise
            rescue Shoko::Error => e
              @logger&.debug('Pending jump apply failed', error: e.message)
            end
          end
        end
      end
    end
  end
end
