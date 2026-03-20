# frozen_string_literal: true

require_relative '../support/message_notifier'

module Shoko
  module Adapters
    module Input
      module Controllers
        module Sidebar
          # Owns sidebar open/close/tab-switch orchestration and related state writes.
          class TabStateOrchestrator
            include Shoko::Adapters::Input::Controllers::Support::MessageNotifier

            def initialize(
              config_reader:,
              reader_state_reader:,
              sidebar_state_reader:,
              reader_session_mutator:,
              toc_navigation:,
              document_reader:,
              ui_controller: nil,
              notification_service: nil
            )
              @config_reader = config_reader
              @reader_state_reader = reader_state_reader
              @sidebar_state_reader = sidebar_state_reader
              @reader_session_mutator = reader_session_mutator
              @toc_navigation = toc_navigation
              @document_reader = document_reader
              @ui_controller = ui_controller
              @notification_service = notification_service
              raise ArgumentError, 'notification_service is required' if @notification_service.nil?
            end

            def open_toc
              toggle_sidebar(:toc)
            rescue Shoko::Error => e
              set_message("TOC error: #{e.message}", 3)
            end

            def open_bookmarks
              toggle_sidebar(:bookmarks)
            end

            def open_annotations_tab
              toggle_sidebar(:annotations)
            end

            def activate_sidebar_tab(tab)
              if sidebar_visible?
                switch_sidebar_tab(tab)
              else
                open_sidebar_for(tab)
              end
            rescue Shoko::Error => e
              set_message("Sidebar error: #{e.message}", 3)
            end

            def sidebar_visible?
              @sidebar_state_reader.sidebar_visible?
            end

            def close_sidebar_with_restore(tab)
              prev_mode = @sidebar_state_reader.sidebar_prev_view_mode
              if prev_mode
                @reader_session_mutator.update_config(view_mode: prev_mode)
                @reader_session_mutator.update_reader(sidebar_prev_view_mode: nil)
              end
              @reader_session_mutator.update_sidebar(visible: false)
              @reader_session_mutator.update_reader(mode: :read)
              set_message("#{tab.to_s.capitalize} closed", 1) unless tab == :toc
            end

            private

            def toggle_sidebar(tab)
              close_annotations_overlay_via_ui_controller
              if sidebar_visible?
                return close_sidebar_with_restore(tab) if sidebar_open_for?(tab)

                switch_sidebar_tab(tab)
              else
                open_sidebar_for(tab)
              end
            end

            def sidebar_open_for?(tab)
              @sidebar_state_reader.sidebar_visible? &&
                @sidebar_state_reader.sidebar_active_tab == tab
            end

            def open_sidebar_for(tab)
              @reader_session_mutator.update_reader(sidebar_prev_view_mode: @config_reader.view_mode)
              @reader_session_mutator.update_config(view_mode: :single)
              @reader_session_mutator.update_sidebar(
                **sidebar_updates_for(tab, preserve_selection: false, visible: true)
              )
              @reader_session_mutator.update_reader(mode: :read)
              announce_sidebar(tab, 'opened')
            end

            def switch_sidebar_tab(tab)
              return unless sidebar_visible?
              return if @sidebar_state_reader.sidebar_active_tab == tab

              @reader_session_mutator.update_sidebar(**sidebar_updates_for(tab, preserve_selection: true))
            end

            def close_annotations_overlay_via_ui_controller
              @ui_controller&.close_annotations_overlay
            end

            def document
              @document_reader.call
            end

            def sidebar_updates_for(tab, preserve_selection:, visible: nil)
              updates = { active_tab: tab }
              updates[:visible] = visible unless visible.nil?
              updates.merge!(tab_selection_updates(tab, preserve_selection: preserve_selection))
              updates
            end

            def tab_selection_updates(tab, preserve_selection:)
              case tab
              when :toc
                toc_sidebar_updates(preserve_selection: preserve_selection)
              when :annotations
                { annotations_selected: @sidebar_state_reader.sidebar_annotations_selected || 0 }
              when :bookmarks
                { bookmarks_selected: @sidebar_state_reader.sidebar_bookmarks_selected || 0 }
              else
                {}
              end
            end

            def toc_sidebar_updates(preserve_selection:)
              entries = @toc_navigation.entries_for(document)
              collapsed = @toc_navigation.collapsed_for(entries, @sidebar_state_reader.sidebar_toc_collapsed)
              selected = preserve_selection ? preserved_toc_selection(entries) : current_toc_selection(entries)
              {
                toc_collapsed: collapsed,
                toc_selected: @toc_navigation.ensure_visible_selection(entries, collapsed, selected),
              }
            end

            def preserved_toc_selection(entries)
              selected = @sidebar_state_reader.sidebar_toc_selected
              return selected unless selected.nil?

              current_toc_selection(entries)
            end

            def current_toc_selection(entries)
              current_chapter = (@reader_state_reader.current_chapter || 0).to_i
              @toc_navigation.index_for_chapter(entries, current_chapter)
            end

            def announce_sidebar(tab, action)
              set_message("#{tab.to_s.capitalize} #{action}", 1) unless tab == :toc
            end
          end
        end
      end
    end
  end
end
