# frozen_string_literal: true

require_relative '../../../core/ports/outbound/app_config_store'
require_relative '../../../core/ports/outbound/reader_session_store'
require_relative 'reader_ui_session_registry'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-local write surface over reader/config session snapshots.
        class ReaderSessionMutator
          LIVE_UI_FIELDS = ReaderUiSessionRegistry::LIVE_FIELDS
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

          def initialize(reader_session_store:, app_config_store:, ui_session_registry: nil)
            unless reader_session_store.is_a?(Shoko::Core::Ports::Outbound::ReaderSessionStore)
              raise ArgumentError, 'reader_session_store must implement Core::Ports::Outbound::ReaderSessionStore'
            end
            unless app_config_store.is_a?(Shoko::Core::Ports::Outbound::AppConfigStore)
              raise ArgumentError, 'app_config_store must implement Core::Ports::Outbound::AppConfigStore'
            end
            if !ui_session_registry.nil? && !ui_session_registry.is_a?(ReaderUiSessionRegistry)
              raise ArgumentError, 'ui_session_registry must be a ReaderUiSessionRegistry'
            end

            @reader_session_store = reader_session_store
            @app_config_store = app_config_store
            @ui_session_registry = ui_session_registry
          end

          def update_reader(attributes)
            persist_reader(**attributes)
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

          def update_terminal_size(width, height)
            persist_reader(last_width: width.to_i, last_height: height.to_i)
          end

          private

          def persist_reader(**attributes)
            return if attributes.empty?

            live_ui_attributes, snapshot_attributes = split_live_ui_attributes(attributes)
            previous_live_ui = persist_live_ui(live_ui_attributes)

            snapshot = @reader_session_store.load
            @reader_session_store.save(snapshot.with(**snapshot_attributes)) unless snapshot_attributes.empty?
          rescue Shoko::Error, ArgumentError
            rollback_live_ui(previous_live_ui)
            raise
          end

          def persist_config(**attributes)
            return if attributes.empty?

            snapshot = @app_config_store.load
            @app_config_store.save(snapshot.with(**attributes))
          end

          def split_live_ui_attributes(attributes)
            attributes.each_with_object([{}, {}]) do |(field, value), (live_ui, snapshot_fields)|
              target = LIVE_UI_FIELDS.include?(field) ? live_ui : snapshot_fields
              target[field] = value
            end
          end

          def persist_live_ui(attributes)
            return nil if attributes.empty?

            ensure_ui_session_registry!
            previous = @ui_session_registry.slice(attributes.keys)
            @ui_session_registry.write(attributes)
            previous
          end

          def rollback_live_ui(previous_live_ui)
            return if previous_live_ui.nil? || previous_live_ui.empty? || @ui_session_registry.nil?

            @ui_session_registry.write(previous_live_ui)
          rescue Shoko::Error, ArgumentError => rollback_error
            @last_live_ui_rollback_error = rollback_error
          end

          def ensure_ui_session_registry!
            return if @ui_session_registry

            raise ArgumentError, 'ui_session_registry is required for live reader UI fields'
          end
        end
      end
    end
  end
end
