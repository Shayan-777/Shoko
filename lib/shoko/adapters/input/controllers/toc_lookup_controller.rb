# frozen_string_literal: true

require_relative 'support/message_notifier'
require_relative 'support/session_outcome_access'
require 'shoko/core/services/toc_tree_service'
require 'shoko/shared/text_sanitizer'

module Shoko
  module Adapters
    module Input
      module Controllers
        # Drives the Table-of-Contents panel as a first-class reader mode, mirroring
        # the in-book search controller. Query/selection live in the reader view-state
        # store and are written through the TOC UI session (the panel re-renders from
        # them); this controller owns the operations that need the document: building
        # the filtered, navigable entry view from the TOC tree, moving the selection
        # across navigable rows, and jumping to the chosen chapter (with a finer
        # in-chapter anchor offset when the entry's href resolves to one).
        class TocLookupController
          include Shoko::Adapters::Input::Controllers::Support::MessageNotifier
          include Shoko::Adapters::Input::Controllers::Support::SessionOutcomeAccess

          def initialize(reader_state:, navigation_service:, state_controller:, document_reader:,
                         toc_ui_session:, anchor_resolver: nil, input_controller: nil,
                         notification_service: nil, logger: nil, tree_service: nil)
            @reader_state = reader_state
            @navigation_service = navigation_service
            @state_controller = state_controller
            @document_reader = document_reader
            @toc_ui_session = toc_ui_session
            @anchor_resolver = anchor_resolver
            @input_controller = input_controller
            @notification_service = notification_service
            @logger = logger
            @tree = tree_service || Core::Services::TocTreeService.instance
            raise ArgumentError, 'notification_service is required' if @notification_service.nil?
          end

          def open_toc_lookup(_key = nil)
            outcome = @toc_ui_session.open
            return :pass unless session_ok?(outcome)

            view = build_view('')
            publish_view('', view, initial_selection(view))
            activate_toc_mode
            set_message('Contents: type to filter · ↵ jump · Esc close', 2)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('toc.open_failed', error: e.message)
            :pass
          end

          def close_toc_lookup(_key = nil)
            return :pass unless @toc_ui_session.visible? || @reader_state.mode == :toc

            outcome = @toc_ui_session.close
            return :pass unless session_ok?(outcome)

            deactivate_toc_mode
            :handled
          rescue Shoko::Error => e
            @logger&.debug('toc.close_failed', error: e.message)
            :pass
          end

          def edit_toc_filter(edit_op)
            query = apply_edit(current_query, edit_op)
            view = build_view(query)
            publish_view(query, view, first_selectable(view) || 0)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('toc.filter_failed', error: e.message)
            :pass
          end

          def move_toc_selection(delta)
            view = build_view(current_query)
            positions = selectable_positions(view)
            return :handled if positions.empty?

            target = @tree.target_index(positions, current_selected, delta)
            @toc_ui_session.apply_selection(target)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('toc.move_failed', error: e.message)
            :pass
          end

          def activate_toc_selection(_key = nil)
            view = build_view(current_query)
            entry = selected_entry(view)
            return :pass unless entry&.chapter_index

            jump_to_entry(entry)
            close_toc_lookup
            set_message("Jumped to #{entry.title}", 2)
            :handled
          rescue Shoko::Error => e
            @logger&.debug('toc.activate_failed', error: e.message)
            :pass
          end

          def refresh_theme(theme_context:)
            @toc_ui_session&.refresh_theme(color_mode: theme_context&.color_mode)
          end

          def toc_lookup_visible?
            @toc_ui_session.visible? == true
          end

          private

          # ----- view construction -----

          # Builds the rows the panel renders plus the mapping back to full TOC
          # indices for jumping. Entries are always fully expanded; the filter,
          # when present, keeps matching titles and their ancestors (TocTreeService).
          def build_view(query)
            entries = Array(@tree.entries_for(current_document))
            filter_active = !query.to_s.strip.empty?
            visible = @tree.visible_indices(
              entries, collapsed: [], filter_text: query.to_s, filter_active: filter_active
            )
            current_full = entries.find_index { |entry| entry&.chapter_index == current_chapter }

            { entries: entries, visible: visible, rows: build_rows(entries, visible, current_full) }
          end

          def build_rows(entries, visible, current_full)
            visible.map do |full_idx|
              entry = entries[full_idx]
              {
                title: entry.title.to_s,
                level: entry.level.to_i,
                current: !current_full.nil? && full_idx == current_full,
                navigable: !entry.chapter_index.nil?,
              }
            end
          end

          def publish_view(query, view, selected_index)
            @toc_ui_session.apply_view(query: query, entries: view[:rows], selected_index: selected_index)
          end

          # ----- selection mechanics (over navigable rows only) -----

          def selectable_positions(view)
            view[:rows].each_index.select { |pos| view[:rows][pos][:navigable] }
          end

          def first_selectable(view)
            selectable_positions(view).first
          end

          def initial_selection(view)
            positions = selectable_positions(view)
            return 0 if positions.empty?

            current_full = view[:entries].find_index { |entry| entry&.chapter_index == current_chapter }
            here = current_full && view[:visible].index(current_full)
            here && positions.include?(here) ? here : positions.first
          end

          def selected_entry(view)
            sel = current_selected.clamp(0, [view[:rows].length - 1, 0].max)
            full_idx = view[:visible][sel]
            full_idx && view[:entries][full_idx]
          end

          # ----- jumping -----

          def jump_to_entry(entry)
            chapter_index = entry.chapter_index
            offset = @anchor_resolver&.line_offset_for_toc_entry(entry, chapter_index)
            if offset
              @state_controller.jump_to_chapter_offset(chapter_index, offset)
            else
              @navigation_service&.jump_to_chapter(chapter_index)
            end
          end

          # ----- input plumbing -----

          def apply_edit(query, edit_op)
            case edit_op&.operation
            when :insert    then insert_text(query, edit_op.text)
            when :backspace then query.to_s[0...-1].to_s
            else query.to_s
            end
          end

          def insert_text(query, text)
            return query.to_s unless Shoko::Shared::TextSanitizer.printable_char?(text.to_s)

            "#{query}#{text}"
          end

          def activate_toc_mode
            @input_controller&.enter_modal_mode(:toc)
          end

          def deactivate_toc_mode
            @input_controller&.exit_modal_mode(:toc)
          end

          def current_document
            @document_reader&.call
          end

          def current_query
            @reader_state.toc_query.to_s
          end

          def current_selected
            (@reader_state.toc_selected_index || 0).to_i
          end

          def current_chapter
            (@reader_state.current_chapter || 0).to_i
          end
        end
      end
    end
  end
end
