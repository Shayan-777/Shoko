# frozen_string_literal: true

require_relative '../../../core/ports/outbound/app_config_store'
require_relative '../../../core/ports/outbound/reader_session_store'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-local write surface over reader/config session snapshots.
        class ReaderSessionMutator
          SIDEBAR_FIELD_MAP = {
            visible: :sidebar_visible,
            active_tab: :sidebar_active_tab,
            toc_selected: :sidebar_toc_selected,
            annotations_selected: :sidebar_annotations_selected,
            bookmarks_selected: :sidebar_bookmarks_selected,
            toc_filter: :sidebar_toc_filter,
            toc_filter_active: :sidebar_toc_filter_active,
            toc_collapsed: :sidebar_toc_collapsed,
          }.freeze

          def initialize(reader_session_store:, app_config_store:)
            unless reader_session_store.is_a?(Shoko::Core::Ports::Outbound::ReaderSessionStore)
              raise ArgumentError, 'reader_session_store must implement Core::Ports::Outbound::ReaderSessionStore'
            end
            unless app_config_store.is_a?(Shoko::Core::Ports::Outbound::AppConfigStore)
              raise ArgumentError, 'app_config_store must implement Core::Ports::Outbound::AppConfigStore'
            end

            @reader_session_store = reader_session_store
            @app_config_store = app_config_store
          end

          def update_pagination_state(attributes)
            persist_reader(**attributes)
          end

          def update_page(attributes)
            persist_reader(**attributes)
          end

          def update_selections(attributes)
            persist_reader(**attributes)
          end

          def update_ui_loading(attributes)
            persist_reader(**attributes)
          end

          def update_reader(attributes)
            persist_reader(**attributes)
          end

          def update_navigation(attributes)
            persist_reader(**attributes)
          end

          def update_bookmarks(bookmarks)
            persist_reader(bookmarks: bookmarks)
          end

          def update_config(attributes)
            persist_config(**attributes)
          end

          def update_sidebar(attributes)
            mapped = attributes.each_with_object({}) do |(field, value), updates|
              updates[SIDEBAR_FIELD_MAP.fetch(field, field)] = value
            end
            persist_reader(**mapped)
          end

          def update_annotations(annotations)
            persist_reader(annotations: annotations)
          end

          def clear_selection
            persist_reader(selection: nil)
          end

          def quit_to_menu
            persist_reader(running: false)
          end

          def toggle_view_mode
            config = @app_config_store.load
            next_mode = config.view_mode == :single ? :split : :single
            @app_config_store.save(config.with(view_mode: next_mode))
          end

          def update_reader_meta(attributes)
            persist_reader(**attributes)
          end

          def update_terminal_size(width, height)
            persist_reader(last_width: width.to_i, last_height: height.to_i)
          end

          private

          def persist_reader(**attributes)
            return if attributes.empty?

            snapshot = @reader_session_store.load
            @reader_session_store.save(snapshot.with(**attributes))
          end

          def persist_config(**attributes)
            return if attributes.empty?

            snapshot = @app_config_store.load
            @app_config_store.save(snapshot.with(**attributes))
          end
        end
      end
    end
  end
end
