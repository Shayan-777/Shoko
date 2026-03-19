# frozen_string_literal: true

require_relative 'sidebar/toc_navigation'
require_relative 'sidebar/anchor_resolver'
require_relative 'sidebar/tab_state_orchestrator'
require_relative 'sidebar/toc_facade'
require_relative 'sidebar/selection_coordinator'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Coordinates sidebar interactions while delegating focused logic to collaborators.
        class SidebarController
          Dependencies = Data.define(
            :reader_state,
            :config_reader,
            :ui_state,
            :sidebar_state,
            :reader_session_mutator,
            :document,
            :document_reader,
            :navigation_service,
            :bookmark_service,
            :state_controller,
            :ui_controller,
            :notification_service,
            :formatting_service,
            :layout_service
          ) do
            REQUIRED_FIELDS = %i[
              reader_state
              config_reader
              ui_state
              sidebar_state
              reader_session_mutator
            ].freeze

            def validate!
              missing = []
              missing << :reader_state if reader_state.nil?
              missing << :config_reader if config_reader.nil?
              missing << :ui_state if ui_state.nil?
              missing << :sidebar_state if sidebar_state.nil?
              missing << :reader_session_mutator if reader_session_mutator.nil?
              return self if missing.empty?

              raise ArgumentError, "Missing required sidebar controller dependencies: #{missing.join(', ')}"
            end
          end

          include Sidebar::TocFacade

          def initialize(deps:)
            deps.validate!

            @reader_state = deps.reader_state
            @config_reader = deps.config_reader
            @ui_state = deps.ui_state
            @sidebar_state = deps.sidebar_state
            @reader_session_mutator = deps.reader_session_mutator
            @document = deps.document
            @document_reader = deps.document_reader
            @navigation_service = deps.navigation_service
            @bookmark_service = deps.bookmark_service
            @state_controller = deps.state_controller
            @ui_controller = deps.ui_controller
            @notification_service = deps.notification_service
            @formatting_service = deps.formatting_service
            @layout_service = deps.layout_service

            @toc_navigation = Sidebar::TocNavigation.new
            @anchor_resolver = Sidebar::AnchorResolver.new(
              document_reader: -> { current_document },
              formatting_service: @formatting_service,
              layout_service: @layout_service,
              ui_state_reader: @ui_state,
              config_reader: @config_reader,
              sidebar_state_reader: @sidebar_state
            )
            @tab_state_orchestrator = Sidebar::TabStateOrchestrator.new(
              config_reader: @config_reader,
              reader_state_reader: @reader_state,
              sidebar_state_reader: @sidebar_state,
              reader_session_mutator: @reader_session_mutator,
              toc_navigation: @toc_navigation,
              document_reader: -> { current_document },
              ui_controller: @ui_controller,
              notification_service: @notification_service
            )
            @selection_coordinator = Sidebar::SelectionCoordinator.new(
              state: Sidebar::SelectionCoordinator::StateDependencies.build(
                reader_state_reader: @reader_state,
                sidebar_state_reader: @sidebar_state,
                reader_session_mutator: @reader_session_mutator,
                navigation_service: @navigation_service,
                bookmark_service: @bookmark_service,
                state_controller: @state_controller,
                close_sidebar: ->(tab) { close_sidebar_with_restore(tab) },
                sidebar_visible: -> { sidebar_visible? }
              ),
              toc: Sidebar::SelectionCoordinator::TocDependencies.build(
                toc_entries_for: ->(document) { toc_entries_for(document) },
                toc_collapsed_for: ->(entries, raw = nil) { toc_collapsed_for(entries, raw) },
                toc_filter_active: -> { toc_filter_active? },
                toc_entry_has_children: ->(entries, index) { toc_entry_has_children?(entries, index) },
                ensure_visible_toc_selection: lambda { |entries, collapsed, current|
                  ensure_visible_toc_selection(entries, collapsed, current)
                },
                navigable_toc_entry_indices: ->(entries, collapsed) { navigable_toc_entry_indices(entries, collapsed) },
                find_toc_target: ->(indices, current, delta) { find_toc_target(indices, current, delta) },
                toggle_toc_collapsed: ->(collapsed, index) { toggle_toc_collapsed(collapsed, index) },
                line_offset_for_toc_entry: ->(entry, chapter_index) { line_offset_for_toc_entry(entry, chapter_index) }
              )
            )
          end

          def open_toc
            @tab_state_orchestrator.open_toc
          end

          def open_bookmarks
            @tab_state_orchestrator.open_bookmarks
          end

          def open_annotations_tab
            @tab_state_orchestrator.open_annotations_tab
          end

          def activate_sidebar_tab(tab)
            @tab_state_orchestrator.activate_sidebar_tab(tab)
          end

          def handle_sidebar_toc_click(index)
            @selection_coordinator.handle_toc_click(index, document: current_document)
          end

          def select_sidebar_toc_index(index)
            @selection_coordinator.set_toc_selected(index, document: current_document)
          end

          # Sidebar navigation helpers
          def sidebar_down
            @selection_coordinator.move(+1, document: current_document)
          end

          def sidebar_up
            @selection_coordinator.move(-1, document: current_document)
          end

          def sidebar_select
            @selection_coordinator.select(document: current_document)
          end

          def sidebar_toggle_toc
            @selection_coordinator.toggle_toc(document: current_document)
          end

          def sidebar_visible?
            @tab_state_orchestrator.sidebar_visible?
          end

          def close_sidebar_with_restore(tab)
            @tab_state_orchestrator.close_sidebar_with_restore(tab)
          end

          private

          def find_toc_target(indices, current, delta)
            @toc_navigation.target_index(indices, current, delta)
          end

          def line_offset_for_toc_entry(entry, chapter_index)
            @anchor_resolver.line_offset_for_toc_entry(entry, chapter_index)
          end

          def current_document
            @document_reader&.call || @document
          end
        end
      end
    end
  end
end
