# frozen_string_literal: true

require_relative '../../../core/ports/outbound/app_config_store'
require_relative '../../../core/ports/outbound/reader_session_store'
require_relative '../../../core/ports/outbound/reader_view_state_store'
require_relative '../../../core/ports/outbound/reader_pagination_store'
require_relative '../../../core/models/session/reader_session_snapshot'
require_relative '../../../core/models/session/reader_view_state_snapshot'
require_relative '../../../core/models/session/reader_pagination_snapshot'
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
          SESSION_FIELDS = Shoko::Core::Models::Session::ReaderSessionSnapshotFields.freeze
          VIEW_FIELDS = Shoko::Core::Models::Session::ReaderViewStateSnapshotFields.freeze
          PAGINATION_FIELDS = Shoko::Core::Models::Session::ReaderPaginationSnapshotFields.freeze

          def initialize(
            reader_session_store:,
            app_config_store:,
            reader_view_state_store: nil,
            reader_pagination_store: nil,
            ui_session_registry: nil
          )
            validate_dependencies!(
              reader_session_store: reader_session_store,
              app_config_store: app_config_store,
              reader_view_state_store: reader_view_state_store,
              reader_pagination_store: reader_pagination_store,
              ui_session_registry: ui_session_registry
            )
            assign_dependencies(
              reader_session_store: reader_session_store,
              app_config_store: app_config_store,
              reader_view_state_store: reader_view_state_store,
              reader_pagination_store: reader_pagination_store,
              ui_session_registry: ui_session_registry
            )
          end

          def update_reader(attributes)
            persist_reader(**attributes)
          end

          def update_config(attributes)
            persist_config(**attributes)
          end

          def update_sidebar(attributes)
            mapped = attributes.transform_keys do |field|
              SIDEBAR_FIELD_MAP.fetch(field, field)
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

            live_ui_attributes, session_attributes, view_attributes, pagination_attributes =
              split_reader_attributes(attributes)
            previous_live_ui = persist_live_ui(live_ui_attributes)
            rollback_actions = []

            persist_snapshot_store(@reader_session_store, session_attributes, rollback_actions)
            persist_snapshot_store(@reader_view_state_store, view_attributes, rollback_actions)
            persist_snapshot_store(@reader_pagination_store, pagination_attributes, rollback_actions)
          rescue Shoko::Error, ArgumentError
            rollback_snapshots(rollback_actions)
            rollback_live_ui(previous_live_ui)
            raise
          end

          def persist_config(**attributes)
            return if attributes.empty?

            snapshot = @app_config_store.load
            @app_config_store.save(snapshot.with(**attributes))
          end

          def split_reader_attributes(attributes)
            attributes.each_with_object([{}, {}, {}, {}]) do |(field, value), targets|
              live_ui, session_fields, view_fields, pagination_fields = targets
              if LIVE_UI_FIELDS.include?(field)
                live_ui[field] = value
              elsif VIEW_FIELDS.include?(field)
                view_fields[field] = value
              elsif PAGINATION_FIELDS.include?(field)
                pagination_fields[field] = value
              else
                session_fields[field] = value
              end
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
          rescue Shoko::Error, ArgumentError => e
            @last_live_ui_rollback_error = e
          end

          def ensure_ui_session_registry!
            return if @ui_session_registry

            raise ArgumentError, 'ui_session_registry is required for live reader UI fields'
          end

          def persist_snapshot_store(store, attributes, rollback_actions)
            return if attributes.empty?
            raise ArgumentError, 'required reader state store is missing for persisted attributes' if store.nil?

            previous_snapshot = store.load
            store.save(previous_snapshot.with(**attributes))
            rollback_actions << [store, previous_snapshot]
          end

          def rollback_snapshots(rollback_actions)
            rollback_actions.reverse_each do |store, snapshot|
              store.save(snapshot)
            rescue Shoko::Error, ArgumentError => e
              @last_snapshot_rollback_error = e
            end
          end

          def validate_dependencies!(reader_session_store:, app_config_store:, reader_view_state_store:,
                                     reader_pagination_store:, ui_session_registry:)
            validate_required_store!(reader_session_store,
                                     Shoko::Core::Ports::Outbound::ReaderSessionStore,
                                     'reader_session_store must implement Core::Ports::Outbound::ReaderSessionStore')
            validate_required_store!(app_config_store,
                                     Shoko::Core::Ports::Outbound::AppConfigStore,
                                     'app_config_store must implement Core::Ports::Outbound::AppConfigStore')
            validate_optional_store!(reader_view_state_store,
                                     Shoko::Core::Ports::Outbound::ReaderViewStateStore,
                                     'reader_view_state_store must implement Core::Ports::Outbound::ReaderViewStateStore')
            validate_optional_store!(reader_pagination_store,
                                     Shoko::Core::Ports::Outbound::ReaderPaginationStore,
                                     'reader_pagination_store must implement Core::Ports::Outbound::ReaderPaginationStore')
            validate_optional_store!(ui_session_registry,
                                     ReaderUiSessionRegistry,
                                     'ui_session_registry must be a ReaderUiSessionRegistry')
          end

          def validate_required_store!(value, contract, message)
            raise ArgumentError, message unless value.is_a?(contract)
          end

          def validate_optional_store!(value, contract, message)
            return if value.nil? || value.is_a?(contract)

            raise ArgumentError, message
          end

          def assign_dependencies(reader_session_store:, app_config_store:, reader_view_state_store:,
                                  reader_pagination_store:, ui_session_registry:)
            @reader_session_store = reader_session_store
            @app_config_store = app_config_store
            @reader_view_state_store = reader_view_state_store
            @reader_pagination_store = reader_pagination_store
            @ui_session_registry = ui_session_registry
          end
        end
      end
    end
  end
end
