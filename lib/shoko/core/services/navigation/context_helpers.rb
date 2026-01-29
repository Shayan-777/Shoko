# frozen_string_literal: true

module Shoko
  module Core
    module Services
      module Navigation
        # Helpers for extracting navigation-relevant values from a state snapshot.
        # These are pure functions that work on hash snapshots, keeping them
        # decoupled from specific state store implementations.
        module ContextHelpers
          module_function

          def dynamic_mode?(snapshot)
            mode = snapshot.dig(:config, :page_numbering_mode)
            mode == :dynamic
          end

          def current_view_mode(snapshot)
            snapshot.dig(:config, :view_mode) || :split
          end

          def current_chapter(snapshot)
            snapshot.dig(:reader, :current_chapter) || 0
          end

          def total_chapters(snapshot)
            snapshot.dig(:reader, :total_chapters) || 0
          end

          def current_page_index(snapshot)
            snapshot.dig(:reader, :current_page_index) || 0
          end

          def current_page(snapshot)
            snapshot.dig(:reader, :current_page) || 0
          end

          def single_page(snapshot)
            snapshot.dig(:reader, :single_page) || current_page(snapshot)
          end

          def left_page(snapshot)
            snapshot.dig(:reader, :left_page) || current_page(snapshot)
          end

          def right_page(snapshot)
            snapshot.dig(:reader, :right_page) || 0
          end

          def page_map(snapshot)
            snapshot.dig(:reader, :page_map) || []
          end

          # Build a snapshot hash from ports (for migration to port-based access)
          # This allows ContextBuilder to use ports while ContextHelpers remain pure
          def build_snapshot_from_ports(config_reader:, reader_state_reader:)
            {
              config: {
                page_numbering_mode: config_reader.page_numbering_mode,
                view_mode: config_reader.view_mode,
              },
              reader: {
                current_chapter: reader_state_reader.current_chapter,
                total_chapters: reader_state_reader.total_chapters,
                current_page_index: reader_state_reader.current_page_index,
                current_page: reader_state_reader.current_page,
                single_page: reader_state_reader.single_page,
                left_page: reader_state_reader.left_page,
                right_page: reader_state_reader.right_page,
                page_map: reader_state_reader.page_map,
              },
            }
          end
        end
      end
    end
  end
end
