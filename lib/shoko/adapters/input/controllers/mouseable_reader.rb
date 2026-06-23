# frozen_string_literal: true

require_relative 'reader_controller'
require 'shoko/core/models/selection_anchor'
require_relative 'reader/toc_anchor_resolver'
require_relative 'reader/inline_link_navigator'
require_relative 'mouseable_reader/input_sequence_filter'
require_relative 'mouseable_reader/inline_link_interaction'

module Shoko
  module Adapters
    module Input
      module Controllers
        # A Reader that supports mouse interactions for annotations.
        #
        # Text selection and the right-click context-menu popup are part of this
        # reader's own mouse state machine (they share its mutable selection
        # state — @selected_text, @suppress_popup_release_once — and its ~13 mouse
        # dependencies), so they live here as private methods rather than in a
        # separate collaborator (constitution R1: behavior bound to one host's
        # state belongs on the host).
        class MouseableReader < ReaderController
          # Synthesised keys the overlay mouse router replays onto the active
          # mode's existing bindings.
          OVERLAY_SCROLL_UP_KEY = "\e[A"
          OVERLAY_SCROLL_DOWN_KEY = "\e[B"
          OVERLAY_ACTIVATE_KEY = "\r"
          OVERLAY_DISMISS_KEY = "\e"

          # The reader-state field holding each overlay's selection cursor, written
          # before the activate key so ⏎ confirms the clicked row.
          BAR_OVERLAY_INDEX_FIELDS = {
            in_book_search: :search_selected_index,
            dictionary: :dictionary_selected_index,
            toc: :toc_selected_index,
            translator: :translator_picker_index,
            notes: :notes_selected_index,
          }.freeze

          # Overlay click targets that are buttons (not list rows) and light up
          # under the pointer like a row does.
          HOVERABLE_OVERLAY_ACTIONS = %i[paste_source copy_translation translator_close].freeze

          # Symbol hit-targets that re-enter the use-case layer as a translator intent
          # (the mouse equivalent of Tab / a typed action), mapped to their args.
          OVERLAY_CLICK_INTENTS = {
            picker_source: %i[translator_open_picker source],
            picker_target: %i[translator_open_picker target],
            paste_source: %i[translator_paste_source],
            copy_translation: %i[translator_copy_translation],
          }.freeze

          # The state accessor for each overlay's render component (which owns the
          # frame's hit geometry).
          BAR_OVERLAY_POPUPS = {
            in_book_search: :in_book_search_popup,
            dictionary: :dictionary_lookup_popup,
            toc: :toc_lookup_popup,
            translator: :translator_lookup_popup,
            notes: :notes_lookup_popup,
          }.freeze

          def initialize(
            epub_path,
            core:,
            state:,
            services:,
            runtime_boot:,
            runtime_startup:,
            mouse_support:,
            mouse_handler:,
            runtime_components_factory:, render_state_writer: nil
          )
            super(
              epub_path,
              core: core,
              state: state,
              services: services,
              runtime_boot: runtime_boot,
              runtime_startup: runtime_startup,
              runtime_components_factory: runtime_components_factory
            )

            assign_mouse_dependencies(mouse_support, mouse_handler, render_state_writer)
            validate_mouse_dependencies!
            bootstrap_mouse_state
          end

          def run
            terminal_service.enable_mouse
            drain_input_buffer
            super
          ensure
            terminal_service.disable_mouse
          end

          def drain_input_buffer
            drained = 0
            while terminal_service.read_key
              drained += 1
              break if drained > 20
            end
          end

          def read_input_keys(timeout: nil)
            key = terminal_service.read_input_with_mouse(timeout: timeout)
            return [] unless key

            keys = [key]
            while (extra = terminal_service.read_key)
              keys << extra
              break if keys.size > 10
            end

            filter_mouse_sequences(keys)
          end

          def clear_selection!
            @reader_session_mutator.update_reader(popup_menu: nil, hovered_inline_link: nil)
            @mouse_handler&.reset
            @reader_session_mutator.clear_selection
          end

          private

          def filter_mouse_sequences(keys)
            input_sequence_filter.filter(keys)
          end

          def spurious_post_mouse_key?(token, ctx)
            return (ctx[:saw_mouse] || ctx[:saw_prefix]) && token == "\e" unless @input_sequence_filter

            @input_sequence_filter.spurious_post_mouse_key?(token, ctx)
          end

          def handle_mouse_input(input)
            event = @mouse_handler.parse_mouse_event(input)
            return unless event

            return if handle_bar_overlay_mouse(event)
            return if handle_overlay_click(event)

            handle_content_mouse_event(event)
          end

          # The five bar-anchored overlays (in-book search, dictionary, TOC,
          # translator, notes) are driven by the same per-mode ↑/↓/⏎/Esc bindings
          # the keyboard uses, so mouse just maps onto them:
          #
          #   * the wheel scrolls (synthesised arrows);
          #   * moving over a row previews it (a dim hover highlight tracks the
          #     pointer without disturbing the arrow-key selection);
          #   * pressing a row moves the real selection cursor there;
          #   * releasing activates it (⏎ → jump to that entry);
          #   * pressing/releasing in the book above the panel dismisses it (Esc).
          #
          # While an overlay owns the screen it consumes every mouse event so
          # nothing bleeds through to text selection.
          def handle_bar_overlay_mouse(event)
            mode = active_bar_overlay_mode
            return false unless mode

            if wheel_event?(event)
              feed_overlay_key(wheel_up?(event) ? OVERLAY_SCROLL_UP_KEY : OVERLAY_SCROLL_DOWN_KEY)
            elsif motion_event?(event)
              update_overlay_hover(mode, event)
            elsif left_press?(event)
              move_overlay_selection(mode, event)
            elsif left_release?(event)
              activate_overlay_click(mode, event)
            end
            true
          end

          def handle_overlay_click(event)
            return true if popup_overlay_handled?(event)
            return true if popup_context_click_handled?(event)
            return false unless event[:released]

            if annotation_editor_visible?
              handle_annotation_editor_click(event)
              return true
            end

            return true if content_mouse_blocked?

            false
          end

          def consume_suppressed_popup_release?
            return false unless @suppress_popup_release_once

            @suppress_popup_release_once = false
            true
          end

          def handle_content_mouse_event(event)
            return if content_mouse_blocked?

            hover_changed = sync_inline_link_hover(event)
            if consume_inline_link_click(event)
              draw_screen
              return
            end

            result = @mouse_handler.handle_event(event)
            unless result
              draw_screen if hover_changed
              return
            end

            handle_content_mouse_result(result)
          end

          def handle_annotation_editor_click(event)
            coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
            controller = ui_controller
            result = controller.handle_annotation_editor_overlay_click(coords[:x], coords[:y])
            controller.handle_annotation_editor_overlay_event(result) if result
            @mouse_handler.reset
          ensure
            draw_screen
          end

          # The active bar-overlay mode, or nil when the reader is in normal
          # reading/selection (the annotation editor and the right-click context
          # menu keep their own existing mouse handling).
          def active_bar_overlay_mode
            mode = @reader_state_reader&.mode
            BAR_OVERLAY_INDEX_FIELDS.key?(mode) ? mode : nil
          end

          # SGR wheel reports set bit 6; bit 0 is direction (up=0/down=1) and bit 1
          # marks the horizontal wheel, which we ignore.
          def wheel_event?(event)
            button = event[:button].to_i
            button.allbits?(0x40) && button.nobits?(0x02)
          end

          def wheel_up?(event)
            event[:button].to_i.nobits?(0x01)
          end

          # Pointer-motion report (bit 5), with or without a button held — drives
          # the hover preview.
          def motion_event?(event)
            event[:button].to_i.allbits?(0x20)
          end

          # A left-button press (low bits 0, no motion/wheel bits, not a release).
          def left_press?(event)
            !event[:released] && event[:button].to_i.nobits?(0x63)
          end

          # A left-button release (low bits 0, not a wheel report).
          def left_release?(event)
            event[:released] && event[:button].to_i.nobits?(0x43)
          end

          # Hover preview: light up the row — or the Paste/Copy button — under the
          # pointer (or clear it when off them). The hover target is the row index
          # or the action symbol; only writes/redraws when it actually changes.
          def update_overlay_hover(mode, event)
            target = overlay_hit_target_for_event(mode, event)
            hover = overlay_hover_value(target)
            return if hover == @reader_state_reader&.overlay_hover_index

            @reader_session_mutator.update_reader(overlay_hover_index: hover)
            draw_screen
          end

          def overlay_hover_value(target)
            return target if target.is_a?(Integer)
            return target if HOVERABLE_OVERLAY_ACTIONS.include?(target)

            nil
          end

          # Press moves the real selection cursor to the row under the pointer
          # (and drops the hover preview, since the row is now selected).
          def move_overlay_selection(mode, event)
            target = overlay_hit_target_for_event(mode, event)
            return unless target.is_a?(Integer)

            @reader_session_mutator.update_reader(
              BAR_OVERLAY_INDEX_FIELDS.fetch(mode) => target, overlay_hover_index: nil
            )
            draw_screen
          end

          # Release activates: confirm the row under the pointer (⏎), re-enter a
          # translator affordance (open/flip the picker, Paste, Copy), close the
          # translator from its red box, or dismiss the overlay when the release lands
          # in the book above it (Esc — but never for the translator, which closes
          # only from its box or Esc).
          def activate_overlay_click(mode, event)
            target = overlay_hit_target_for_event(mode, event)
            return activate_overlay_row(mode, target) if target.is_a?(Integer)
            return dismiss_overlay if target == :translator_close
            return dismiss_overlay if target == :outside && mode != :translator

            intent = OVERLAY_CLICK_INTENTS[target]
            dispatch_overlay_intent(*intent) if intent
          end

          def activate_overlay_row(mode, index)
            @reader_session_mutator.update_reader(
              BAR_OVERLAY_INDEX_FIELDS.fetch(mode) => index, overlay_hover_index: nil
            )
            feed_overlay_key(OVERLAY_ACTIVATE_KEY)
          end

          # Esc through the same path keys take: from the translator's editor face
          # this closes it outright. The translator no longer dismisses on a click out
          # in the book — only its red close box (or Esc) closes it — so the book stays
          # put while you reach for the Paste button or the language tabs.
          def dismiss_overlay
            @reader_session_mutator.update_reader(overlay_hover_index: nil)
            feed_overlay_key(OVERLAY_DISMISS_KEY)
          end

          # Clicking a translator affordance (the source/target language label, or
          # the Paste/Copy button) re-enters the use-case layer with that intent —
          # the mouse equivalent of Tab / a typed action.
          def dispatch_overlay_intent(intent, payload = nil)
            @reader_session_mutator.update_reader(overlay_hover_index: nil)
            input_controller&.dispatch_reader_intent(intent, payload)
            draw_screen
          end

          def overlay_hit_target_for_event(mode, event)
            coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
            component = bar_overlay_component(mode)
            return :inside unless component

            component.hit_test(coords[:x], coords[:y])
          end

          def bar_overlay_component(mode)
            accessor = BAR_OVERLAY_POPUPS.fetch(mode)
            @reader_state_reader&.public_send(accessor)
          end

          # Replay a synthesised key through the same dispatch path real keys take,
          # then repaint so the result is immediately visible.
          def feed_overlay_key(key)
            dispatch_input_keys([key])
            draw_screen
          end

          def consume_inline_link_click(event)
            inline_link_interaction.consume_click(event, mouse_handler: @mouse_handler)
          end

          def build_inline_link_navigator(mouse_support)
            Reader::InlineLinkNavigator.new(
              coordinate_service: @coordinate_service,
              rendered_content_reader: @rendered_content_reader,
              reader_state_reader: @reader_state_reader,
              document_reader: -> { doc },
              state_controller: state_controller,
              anchor_resolver: build_anchor_resolver(mouse_support),
              logger: @logger_ref
            )
          end

          def sync_inline_link_hover(event)
            inline_link_interaction.sync_hover(event)
          end

          def popup_overlay_handled?(event)
            return false unless popup_menu_active?

            event[:released] ? handle_popup_release(event) : handle_popup_hover(event)
            true
          end

          def handle_popup_release(event)
            return if consume_suppressed_popup_release?

            handle_popup_click(event)
          end

          def content_mouse_blocked?
            dictionary_popup_visible? || translator_visible? || in_book_search_popup_visible?
          end

          def handle_content_mouse_result(result)
            case result[:type]
            when :selection_drag
              update_state_selection(@mouse_handler.selection_range)
              refresh_highlighting
            when :selection_end
              handle_selection_end
              draw_screen
            else
              draw_screen
            end
          end

          def build_anchor_resolver(mouse_support)
            Reader::TocAnchorResolver.new(
              document_reader: -> { doc },
              formatting_service: mouse_support.formatting_service,
              layout_service: mouse_support.layout_service,
              ui_state_reader: mouse_support.ui_state_reader || @ui_state_reader,
              config_reader: @config_reader
            )
          end

          def input_sequence_filter
            @input_sequence_filter ||= MouseableReaderSupport::InputSequenceFilter.new(
              mouse_handler: @mouse_handler,
              handle_mouse_input: ->(input) { handle_mouse_input(input) }
            )
          end

          def inline_link_interaction
            @inline_link_interaction ||= MouseableReaderSupport::InlineLinkInteraction.new(
              inline_link_navigator: @inline_link_navigator,
              reader_state_reader: @reader_state_reader,
              reader_session_mutator: @reader_session_mutator
            )
          end

          def assign_mouse_dependencies(mouse_support, mouse_handler, render_state_writer)
            @coordinate_service = @coordinate_service_ref
            @popup_position_service = @popup_position_service_ref
            @render_state_writer = render_state_writer
            @mouse_handler = mouse_handler
            @selection_service = @selection_service_ref
            @rendered_content_reader = rendered_content_reader
            @render_registry = @render_registry_ref
            @clipboard_service = clipboard_service
            @dictionary_availability = mouse_support.dictionary_availability
            @ui_component_factory = mouse_support.ui_component_factory
            @reader_session_mutator = reader_session_mutator
            @inline_link_navigator = build_inline_link_navigator(mouse_support)
          end

          def validate_mouse_dependencies!
            raise ArgumentError, 'render_state_writer is required' if @render_state_writer.nil?
            raise ArgumentError, 'annotation_service is required' if @annotation_service_ref.nil?
          end

          def bootstrap_mouse_state
            @reader_session_mutator.update_reader(popup_menu: nil, hovered_inline_link: nil)
            @selected_text = nil
            @reader_session_mutator.clear_selection
            clear_rendered_lines_on_init
            refresh_annotations
          end

          def dictionary_popup_visible?
            popup_ui_controller&.dictionary_visible? == true
          end

          def annotation_editor_visible?
            popup_ui_controller&.annotation_editor_visible? == true
          end

          def in_book_search_popup_visible?
            popup_ui_controller&.in_book_search_visible? == true
          end

          def translator_visible?
            controller = popup_ui_controller
            return false unless controller
            return false unless controller.respond_to?(:translator_visible?)

            controller.translator_visible?
          end

          def popup_menu_active?
            @reader_state_reader.popup_menu&.visible
          end

          def popup_ui_controller
            controllers&.ui_controller
          end

          def refresh_annotations
            annotations = @annotation_service_ref.list_for_book(path)
            @reader_session_mutator.update_reader(annotations: annotations)
          end

          def clear_rendered_lines_on_init
            @render_state_writer.clear_rendered_lines
          end

          # ===== text selection + right-click context menu =====

          def popup_context_click_handled?(event)
            return false unless right_click_press?(event)

            context = popup_context_click_data(event)
            return false unless context

            popup_menu = open_popup_menu(anchor_position: context[:anchor_position])
            @suppress_popup_release_once = true if popup_menu
            !popup_menu.nil?
          end

          def open_popup_menu(anchor_position: nil)
            popup_menu = build_popup_menu(anchor_position: anchor_position)
            return nil unless popup_menu

            @reader_session_mutator.update_reader(popup_menu: popup_menu, popup_menu_selected: 0)
            return nil unless popup_menu.visible

            activate_popup_menu
            popup_menu
          end

          def build_popup_menu(anchor_position: nil)
            selection = @reader_state_reader.selection
            return nil unless selection

            rendered = popup_rendered_lines
            factory = @ui_component_factory
            return nil unless factory

            factory.enhanced_popup_menu(**popup_menu_args(selection, rendered, anchor_position))
          end

          def popup_menu_args(selection, rendered, anchor_position)
            {
              selection: selection,
              coordinate_service: @coordinate_service,
              reader_state_reader: @reader_state_reader,
              reader_session_mutator: @reader_session_mutator,
              popup_position_service: @popup_position_service,
              clipboard_service: @clipboard_service,
              rendered: rendered,
              dictionary_enabled: dictionary_lookup_available?,
              anchor_position: anchor_position,
            }
          end

          def activate_popup_menu
            switch_mode(:popup_menu)
            draw_screen
          end

          def popup_context_click_data(event)
            selection = @reader_state_reader.selection
            rendered = popup_rendered_lines
            return nil unless selection && rendered

            click_anchor = popup_click_anchor(event, rendered)
            return nil unless click_anchor && anchor_within_selection?(click_anchor, selection, rendered)
            return nil unless popup_selected_text(selection)

            { anchor_position: @coordinate_service.mouse_to_terminal(event[:x], event[:y]) }
          end

          def popup_rendered_lines
            rendered = @rendered_content_reader&.rendered_lines
            return nil if rendered.nil? || rendered.empty?

            rendered
          end

          def popup_click_anchor(event, rendered)
            @coordinate_service.anchor_from_point({ x: event[:x], y: event[:y] }, rendered, bias: :nearest)
          end

          def popup_selected_text(selection)
            text = @selected_text || extract_selected_text(selection)
            return nil if text.nil? || text.strip.empty?

            text
          end

          def right_click_press?(event)
            button = event[:button].to_i
            !event[:released] && (button & 0b11) == 2 && button.nobits?(32)
          end

          def anchor_within_selection?(anchor, selection, rendered)
            normalized = @coordinate_service.normalize_selection_range(selection, rendered)
            return false unless normalized

            start_anchor = Shoko::Core::Models::SelectionAnchor.from(normalized[:start])
            end_anchor = Shoko::Core::Models::SelectionAnchor.from(normalized[:end])
            return false unless start_anchor && end_anchor

            (start_anchor <=> anchor).to_i <= 0 && (anchor <=> end_anchor).to_i <= 0
          end

          def handle_popup_click(event)
            terminal_coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
            popup_menu = @reader_state_reader.popup_menu
            item = popup_menu.handle_click(terminal_coords[:x], terminal_coords[:y])

            if item
              handle_popup_action(item)
            else
              @reader_session_mutator.update_reader(popup_menu: nil)
              @mouse_handler.reset
              @reader_session_mutator.clear_selection
            end
            draw_screen
          end

          def handle_popup_hover(event)
            terminal_coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
            popup_menu = @reader_state_reader.popup_menu
            return unless popup_menu

            result = popup_menu.handle_hover(terminal_coords[:x], terminal_coords[:y])
            draw_screen if result && result[:type] == :selection_change
          end

          # The clipboard write is the effect here; the optional on-screen
          # confirmation was never wired (no ui-controller reference on this
          # path). #copy_with_feedback rescues ClipboardError internally and
          # returns false, so no outer rescue is needed.
          def copy_to_clipboard(text)
            clip = @clipboard_service
            return false unless clip

            clip.copy_with_feedback(text)
          end

          def dictionary_lookup_available?
            dict_avail = @dictionary_availability
            return false unless dict_avail
            return false unless dict_avail.sqlite3_available?

            backend = @config_reader.dictionary_backend
            return false if backend.to_s.downcase == 'disabled'

            true
          rescue Shoko::DependencyUnavailableError
            dictionary_lookup_unavailable?
          end

          def dictionary_lookup_unavailable?
            false
          end

          def handle_selection_end
            update_state_selection(@mouse_handler.selection_range)
            selection = @reader_state_reader.selection
            return unless selection

            @selected_text = extract_selected_text(selection)
            return if @selected_text && !@selected_text.strip.empty?

            @mouse_handler.reset
            @reader_session_mutator.clear_selection
          end

          def extract_selected_text(range)
            selection_service = @selection_service
            content_reader = @rendered_content_reader
            return nil unless selection_service && content_reader

            selection_service.extract_text(range, content_reader.rendered_lines)
          end

          def update_state_selection(mouse_range)
            anchor_range = anchor_range_from_mouse(mouse_range)
            if anchor_range
              @reader_session_mutator.update_reader(selection: anchor_range)
            else
              @reader_session_mutator.clear_selection
            end
          end

          def anchor_range_from_mouse(mouse_range)
            return nil unless mouse_range

            rendered = @rendered_content_reader&.rendered_lines
            return nil if rendered.nil? || rendered.empty?

            start_anchor = @coordinate_service.anchor_from_point(mouse_range[:start], rendered, bias: :leading)
            end_anchor = @coordinate_service.anchor_from_point(mouse_range[:end], rendered, bias: :trailing)
            return nil unless start_anchor && end_anchor

            @coordinate_service.normalize_selection_range(
              { start: start_anchor.to_h, end: end_anchor.to_h }, rendered
            )
          end
        end
      end
    end
  end
end
