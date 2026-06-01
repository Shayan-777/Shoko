# frozen_string_literal: true

require_relative 'dependencies/sidebar_controller_dependencies'
require_relative 'sidebar/toc_navigation'
require_relative 'sidebar/anchor_resolver'
require_relative 'sidebar/tab_state_orchestrator'
require_relative 'sidebar/selection_coordinator'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Coordinates sidebar interactions while delegating focused logic to collaborators.
        class SidebarController
          Dependencies = Shoko::Adapters::Input::Controllers::Dependencies::SidebarControllerDependencies::Bundle


          def initialize(deps:)
            dependencies = deps.validate!
            assign_state_dependencies(dependencies.state)
            assign_service_dependencies(dependencies.services)
            assign_ui_dependencies(dependencies.ui)
            build_sidebar_collaborators
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


          def toc_entries_for(doc)
            @toc_navigation.entries_for(doc)
          end

          def toc_collapsed_for(entries, raw = nil)
            raw = @sidebar_state.sidebar_toc_collapsed if raw.nil?
            @toc_navigation.collapsed_for(entries, raw)
          end

          def toc_visible_indices(entries, collapsed)
            @toc_navigation.visible_indices(
              entries,
              collapsed,
              filter_text: toc_filter_text,
              filter_active: toc_filter_active?
            )
          end

          def toc_entry_has_children?(entries, index)
            @toc_navigation.entry_has_children?(entries, index)
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

          def assign_state_dependencies(deps)
            @reader_state = deps.reader_state
            @config_reader = deps.config_reader
            @ui_state = deps.ui_state
            @sidebar_state = deps.sidebar_state
            @reader_session_mutator = deps.reader_session_mutator
            @document = deps.document
            @document_reader = deps.document_reader
          end

          def assign_service_dependencies(deps)
            @navigation_service = deps.navigation_service
            @bookmark_service = deps.bookmark_service
            @state_controller = deps.state_controller
            @ui_controller = deps.ui_controller
            @notification_service = deps.notification_service
          end

          def assign_ui_dependencies(deps)
            @formatting_service = deps.formatting_service
            @layout_service = deps.layout_service
          end

          def build_sidebar_collaborators
            @toc_navigation = Sidebar::TocNavigation.new
            @anchor_resolver = build_anchor_resolver
            @tab_state_orchestrator = build_tab_state_orchestrator
            @selection_coordinator = build_selection_coordinator
          end

          def build_anchor_resolver
            Sidebar::AnchorResolver.new(
              document_reader: -> { current_document },
              formatting_service: @formatting_service,
              layout_service: @layout_service,
              ui_state_reader: @ui_state,
              config_reader: @config_reader,
              sidebar_state_reader: @sidebar_state
            )
          end

          def build_tab_state_orchestrator
            Sidebar::TabStateOrchestrator.new(
              config_reader: @config_reader,
              reader_state_reader: @reader_state,
              sidebar_state_reader: @sidebar_state,
              reader_session_mutator: @reader_session_mutator,
              toc_navigation: @toc_navigation,
              document_reader: -> { current_document },
              ui_controller: @ui_controller,
              notification_service: @notification_service
            )
          end

          def build_selection_coordinator
            Sidebar::SelectionCoordinator.new(
              state: build_selection_state_dependencies,
              toc: build_selection_toc_dependencies
            )
          end

          def build_selection_state_dependencies
            Sidebar::SelectionCoordinator::StateDependencies.build(
              reader_state_reader: @reader_state,
              sidebar_state_reader: @sidebar_state,
              reader_session_mutator: @reader_session_mutator,
              navigation_service: @navigation_service,
              bookmark_service: @bookmark_service,
              state_controller: @state_controller,
              close_sidebar: ->(tab) { close_sidebar_with_restore(tab) },
              sidebar_visible: -> { sidebar_visible? }
            )
          end

          def build_selection_toc_dependencies
            Sidebar::SelectionCoordinator::TocDependencies.build(
              **toc_visibility_callbacks,
              **toc_navigation_callbacks
            )
          end

          def toc_visibility_callbacks
            {
              toc_entries_for: ->(document) { toc_entries_for(document) },
              toc_collapsed_for: ->(entries, raw = nil) { toc_collapsed_for(entries, raw) },
              toc_filter_active: -> { toc_filter_active? },
              toc_entry_has_children: ->(entries, index) { toc_entry_has_children?(entries, index) },
              ensure_visible_toc_selection: lambda { |entries, collapsed, current|
                ensure_visible_toc_selection(entries, collapsed, current)
              },
            }
          end

          def toc_navigation_callbacks
            {
              navigable_toc_entry_indices: ->(entries, collapsed) { navigable_toc_entry_indices(entries, collapsed) },
              find_toc_target: ->(indices, current, delta) { find_toc_target(indices, current, delta) },
              toggle_toc_collapsed: ->(collapsed, index) { toggle_toc_collapsed(collapsed, index) },
              line_offset_for_toc_entry: ->(entry, chapter_index) { line_offset_for_toc_entry(entry, chapter_index) },
            }
          end


          def toggle_toc_collapsed(collapsed, index)
            @toc_navigation.toggle_collapsed(collapsed, index)
          end

          def ensure_visible_toc_selection(entries, collapsed, current)
            @toc_navigation.ensure_visible_selection(
              entries,
              collapsed,
              current,
              filter_text: toc_filter_text,
              filter_active: toc_filter_active?
            )
          end

          def navigable_toc_entry_indices(entries, collapsed)
            @toc_navigation.navigable_indices(
              entries,
              collapsed,
              filter_text: toc_filter_text,
              filter_active: toc_filter_active?
            )
          end

          def toc_filter_active?
            @sidebar_state.sidebar_toc_filter_active?
          end

          def toc_filter_text
            return '' unless toc_filter_active?

            @sidebar_state.sidebar_toc_filter.to_s
          end

        end
      end
    end
  end
end
