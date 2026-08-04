# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Reader
          # Routes pointer events for the bar-anchored reader overlays through
          # the same intent/key paths used by keyboard input.
          class BarOverlayMouseRouter
            SCROLL_UP_KEY = "\e[A"
            SCROLL_DOWN_KEY = "\e[B"
            ACTIVATE_KEY = "\r"
            DISMISS_KEY = "\e"

            INDEX_FIELDS = {
              in_book_search: :search_selected_index,
              dictionary: :dictionary_selected_index,
              toc: :toc_selected_index,
              translator: :translator_picker_index,
              notes: :notes_selected_index,
            }.freeze

            HOVERABLE_ACTIONS = %i[paste_source copy_translation translator_close].freeze

            CLICK_INTENTS = {
              picker_source: %i[translator_open_picker source],
              picker_target: %i[translator_open_picker target],
              paste_source: %i[translator_paste_source],
              copy_translation: %i[translator_copy_translation],
            }.freeze

            POPUPS = {
              in_book_search: :in_book_search_popup,
              dictionary: :dictionary_lookup_popup,
              toc: :toc_lookup_popup,
              translator: :translator_lookup_popup,
              notes: :notes_lookup_popup,
            }.freeze

            def initialize(reader_state_reader:, reader_session_mutator:, coordinate_service:,
                           dispatch_keys:, dispatch_intent:, draw:)
              @reader_state_reader = reader_state_reader
              @reader_session_mutator = reader_session_mutator
              @coordinate_service = coordinate_service
              @dispatch_keys = dispatch_keys
              @dispatch_intent = dispatch_intent
              @draw = draw
            end

            def handle(event)
              mode = active_mode
              return false unless mode

              if wheel_event?(event)
                feed_key(wheel_up?(event) ? SCROLL_UP_KEY : SCROLL_DOWN_KEY)
              elsif motion_event?(event)
                update_hover(mode, event)
              elsif left_press?(event)
                move_selection(mode, event)
              elsif left_release?(event)
                activate_click(mode, event)
              end
              true
            end

            private

            def active_mode
              mode = @reader_state_reader&.mode
              INDEX_FIELDS.key?(mode) ? mode : nil
            end

            def wheel_event?(event)
              button = event[:button].to_i
              button.allbits?(0x40) && button.nobits?(0x02)
            end

            def wheel_up?(event)
              event[:button].to_i.nobits?(0x01)
            end

            def motion_event?(event)
              event[:button].to_i.allbits?(0x20)
            end

            def left_press?(event)
              !event[:released] && event[:button].to_i.nobits?(0x63)
            end

            def left_release?(event)
              event[:released] && event[:button].to_i.nobits?(0x43)
            end

            def update_hover(mode, event)
              hover = hover_value(hit_target(mode, event))
              return if hover == @reader_state_reader&.overlay_hover_index

              @reader_session_mutator.update_reader(overlay_hover_index: hover)
              @draw.call
            end

            def hover_value(target)
              return target if target.is_a?(Integer)
              return target if HOVERABLE_ACTIONS.include?(target)

              nil
            end

            def move_selection(mode, event)
              target = hit_target(mode, event)
              return unless target.is_a?(Integer)

              @reader_session_mutator.update_reader(
                INDEX_FIELDS.fetch(mode) => target, overlay_hover_index: nil
              )
              @draw.call
            end

            def activate_click(mode, event)
              target = hit_target(mode, event)
              return activate_row(mode, target) if target.is_a?(Integer)
              return dismiss if target == :translator_close
              return dismiss if target == :outside && mode != :translator

              intent = CLICK_INTENTS[target]
              dispatch_overlay_intent(*intent) if intent
            end

            def activate_row(mode, index)
              @reader_session_mutator.update_reader(
                INDEX_FIELDS.fetch(mode) => index, overlay_hover_index: nil
              )
              feed_key(ACTIVATE_KEY)
            end

            def dismiss
              @reader_session_mutator.update_reader(overlay_hover_index: nil)
              feed_key(DISMISS_KEY)
            end

            def dispatch_overlay_intent(intent, payload = nil)
              @reader_session_mutator.update_reader(overlay_hover_index: nil)
              @dispatch_intent.call(intent, payload)
              @draw.call
            end

            def hit_target(mode, event)
              coords = @coordinate_service.mouse_to_terminal(event[:x], event[:y])
              component = popup_component(mode)
              return :inside unless component

              component.hit_test(coords[:x], coords[:y])
            end

            def popup_component(mode)
              @reader_state_reader&.public_send(POPUPS.fetch(mode))
            end

            def feed_key(key)
              @dispatch_keys.call([key])
              @draw.call
            end
          end
        end
      end
    end
  end
end
