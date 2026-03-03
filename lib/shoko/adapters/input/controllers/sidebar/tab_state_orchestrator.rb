# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Sidebar
          # Owns sidebar open/close/tab-switch orchestration and related state writes.
          class TabStateOrchestrator
            def initialize(config_reader:, reader_state_reader:, sidebar_state_reader:, state_writer:, toc_navigation:,
                           document_reader:, ui_controller: nil, notification_service: nil)
              @config_reader = config_reader
              @reader_state_reader = reader_state_reader
              @sidebar_state_reader = sidebar_state_reader
              @state_writer = state_writer
              @toc_navigation = toc_navigation
              @document_reader = document_reader
              @ui_controller = ui_controller
              @notification_service = notification_service
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
                @state_writer.update_config(view_mode: prev_mode)
                @state_writer.update_selections(sidebar_prev_view_mode: nil)
              end
              @state_writer.update_sidebar(visible: false)
              @state_writer.update_reader(mode: :read)
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
              @state_writer.update_selections(
                sidebar_prev_view_mode: @config_reader.view_mode
              )
              @state_writer.update_config(view_mode: :single)

              updates = { active_tab: tab, visible: true }
              case tab
              when :toc
                entries = @toc_navigation.entries_for(document)
                collapsed = @toc_navigation.collapsed_for(entries, @sidebar_state_reader.sidebar_toc_collapsed)
                current_chapter = (@reader_state_reader.current_chapter || 0).to_i
                selected = @toc_navigation.index_for_chapter(entries, current_chapter)
                updates[:toc_collapsed] = collapsed
                updates[:toc_selected] = @toc_navigation.ensure_visible_selection(entries, collapsed, selected)
              when :annotations
                updates[:annotations_selected] = @sidebar_state_reader.sidebar_annotations_selected || 0
              when :bookmarks
                updates[:bookmarks_selected] = @sidebar_state_reader.sidebar_bookmarks_selected || 0
              end

              @state_writer.update_sidebar(**updates)
              @state_writer.update_reader(mode: :read)
              set_message("#{tab.to_s.capitalize} opened", 1) unless tab == :toc
            end

            def switch_sidebar_tab(tab)
              return unless sidebar_visible?

              current_tab = @sidebar_state_reader.sidebar_active_tab
              return if current_tab == tab

              updates = { active_tab: tab }
              case tab
              when :toc
                entries = @toc_navigation.entries_for(document)
                collapsed = @toc_navigation.collapsed_for(entries, @sidebar_state_reader.sidebar_toc_collapsed)
                selected = @sidebar_state_reader.sidebar_toc_selected
                if selected.nil?
                  current_chapter = (@reader_state_reader.current_chapter || 0).to_i
                  selected = @toc_navigation.index_for_chapter(entries, current_chapter)
                end
                updates[:toc_collapsed] = collapsed
                updates[:toc_selected] = @toc_navigation.ensure_visible_selection(entries, collapsed, selected)
              when :annotations
                updates[:annotations_selected] = @sidebar_state_reader.sidebar_annotations_selected || 0
              when :bookmarks
                updates[:bookmarks_selected] = @sidebar_state_reader.sidebar_bookmarks_selected || 0
              end

              @state_writer.update_sidebar(**updates)
            end

            def close_annotations_overlay_via_ui_controller
              @ui_controller&.close_annotations_overlay
            rescue Shoko::Error
              nil
            end

            def set_message(text, duration = 2)
              @notification_service&.set_message(text, duration)
            rescue Shoko::Error
              @state_writer.update_reader(message: text)
            end

            def document
              @document_reader.call
            end
          end
        end
      end
    end
  end
end
