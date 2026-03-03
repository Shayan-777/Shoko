# frozen_string_literal: true

require_relative 'context_helpers'

module Shoko
  module Application
    module Services
      module Reader
        module Navigation
          # Applies absolute-mode changes and computes offsets from layout data.
          class AbsoluteChangeApplier
            CHANGE_PATHS = {
              current_chapter: :current_chapter,
              current_page: :current_page,
              single_page: :single_page,
              left_page: :left_page,
              right_page: :right_page,
            }.freeze

            def initialize(state_updater:, absolute_layout:, image_snapper:, advance_callback:)
              @state_updater = state_updater
              @absolute_layout = absolute_layout
              @image_snapper = image_snapper
              @advance_callback = advance_callback
            end

            def apply(changes)
              return if changes.nil? || changes.empty?

              layout_state = @absolute_layout.build
              return if handle_advance(changes[:advance_chapter], layout_state)

              updates = build_updates(changes)
              updates = apply_align_to_last(updates, changes, layout_state)
              updates = @image_snapper.snap(updates, layout_state) if @image_snapper
              @state_updater.apply(updates)
            end

            private

            def handle_advance(advance, layout_state)
              return false unless advance

              current_chapter = ContextHelpers.current_chapter(layout_state.snapshot)
              case advance
              when :next
                @advance_callback.call(current_chapter + 1)
                true
              when :prev
                previous = current_chapter - 1
                return true if previous.negative?

                offset = @absolute_layout.max_offset_for(layout_state.snapshot, previous, layout_state.stride)
                updates = { current_chapter: previous }
                apply_offset(updates, layout_state, offset)
                @state_updater.apply(updates)
                true
              else
                false
              end
            end

            def build_updates(changes)
              updates = {}
              CHANGE_PATHS.each do |key, path|
                updates[path] = changes[key] if changes.key?(key)
              end
              updates
            end

            def apply_align_to_last(updates, changes, layout_state)
              return updates unless changes[:align_to_last]

              total = ContextHelpers.total_chapters(layout_state.snapshot)
              total = 1 if total.to_i <= 0
              last_chapter = total - 1
              offset = @absolute_layout.max_offset_for(layout_state.snapshot, last_chapter, layout_state.stride)
              updates[:current_chapter] = last_chapter
              apply_offset(updates, layout_state, offset)
              updates
            end

            def apply_offset(updates, layout_state, offset)
              updates[:current_page] = offset
              if layout_state.view_mode == :split
                updates[:left_page] = offset
                updates[:right_page] = offset + layout_state.stride
              else
                updates[:single_page] = offset
              end
              updates
            end
          end
        end
      end
    end
  end
end
