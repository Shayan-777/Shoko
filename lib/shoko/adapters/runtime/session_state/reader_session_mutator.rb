# frozen_string_literal: true

require_relative '../../../application/ports/outbound/app_config_store'
require_relative '../../../application/ports/outbound/reader_session_store'
require_relative '../../../application/ports/outbound/reader_view_state_store'
require_relative '../../../application/ports/outbound/reader_pagination_store'
require_relative '../../../application/ports/outbound/state/reader_session_snapshot'
require_relative '../../../application/ports/outbound/state/reader_view_snapshot'
require_relative '../../../application/ports/outbound/state/reader_pagination_snapshot'
require_relative '../../ui/state/reader_component_registry'

module Shoko
  module Adapters
    module Runtime
      module SessionState
        # Adapter-local write surface that splits a single `update_reader(...)`
        # call across the session, view-state, and pagination stores plus the
        # UI component registry. Live UI component references (popup menus,
        # overlays, panels) are routed to `Adapters::Ui::State::ReaderComponentRegistry`
        # so the application state hash never carries object references.
        class ReaderSessionMutator
          LIVE_UI_FIELDS = Shoko::Adapters::Ui::State::ReaderComponentRegistry::LIVE_FIELDS
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
          SESSION_FIELDS = Shoko::Application::Ports::Outbound::State::ReaderSessionSnapshot::FIELDS.freeze
          VIEW_FIELDS = Shoko::Application::Ports::Outbound::State::ReaderViewSnapshot::FIELDS.freeze
          PAGINATION_FIELDS = Shoko::Application::Ports::Outbound::State::ReaderPaginationSnapshot::FIELDS.freeze

          def initialize(
            reader_session_store:,
            app_config_store:,
            reader_view_state_store: nil,
            reader_pagination_store: nil,
            component_registry: nil
          )
            validate_dependencies!(
              reader_session_store: reader_session_store,
              app_config_store: app_config_store,
              reader_view_state_store: reader_view_state_store,
              reader_pagination_store: reader_pagination_store,
              component_registry: component_registry
            )
            assign_dependencies(
              reader_session_store: reader_session_store,
              app_config_store: app_config_store,
              reader_view_state_store: reader_view_state_store,
              reader_pagination_store: reader_pagination_store,
              component_registry: component_registry
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

            ensure_component_registry!
            previous = @component_registry.slice(attributes.keys)
            @component_registry.write(attributes)
            previous
          end

          def rollback_live_ui(previous_live_ui)
            return if previous_live_ui.nil? || previous_live_ui.empty? || @component_registry.nil?

            @component_registry.write(previous_live_ui)
          rescue Shoko::Error, ArgumentError => e
            @last_live_ui_rollback_error = e
          end

          def ensure_component_registry!
            return if @component_registry

            raise ArgumentError, 'component_registry is required for live reader UI fields'
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
                                     reader_pagination_store:, component_registry:)
            validate_required_store!(reader_session_store,
                                     Shoko::Application::Ports::Outbound::ReaderSessionStore,
                                     'reader_session_store must implement Application::Ports::Outbound::ReaderSessionStore')
            validate_required_store!(app_config_store,
                                     Shoko::Application::Ports::Outbound::AppConfigStore,
                                     'app_config_store must implement Application::Ports::Outbound::AppConfigStore')
            validate_optional_store!(reader_view_state_store,
                                     Shoko::Application::Ports::Outbound::ReaderViewStateStore,
                                     'reader_view_state_store must implement Application::Ports::Outbound::ReaderViewStateStore')
            validate_optional_store!(reader_pagination_store,
                                     Shoko::Application::Ports::Outbound::ReaderPaginationStore,
                                     'reader_pagination_store must implement Application::Ports::Outbound::ReaderPaginationStore')
            validate_optional_store!(component_registry,
                                     Shoko::Adapters::Ui::State::ReaderComponentRegistry,
                                     'component_registry must be an Adapters::Ui::State::ReaderComponentRegistry')
          end

          def validate_required_store!(value, contract, message)
            raise ArgumentError, message unless value.is_a?(contract)
          end

          def validate_optional_store!(value, contract, message)
            return if value.nil? || value.is_a?(contract)

            raise ArgumentError, message
          end

          def assign_dependencies(reader_session_store:, app_config_store:, reader_view_state_store:,
                                  reader_pagination_store:, component_registry:)
            @reader_session_store = reader_session_store
            @app_config_store = app_config_store
            @reader_view_state_store = reader_view_state_store
            @reader_pagination_store = reader_pagination_store
            @component_registry = component_registry
          end
        end
      end
    end
  end
end
