# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Components
        module Ui
          # Stateless throbber used to signal background work (pagination
          # recalculation in the reader, library pre-pagination in the menu).
          #
          # The frame is derived purely from a monotonic clock, so any component
          # can render a consistent, animating glyph without owning timer state.
          # Callers must keep redrawing (e.g. the reader/menu poll loops) for the
          # animation to advance; nothing here drives the loop.
          module Spinner
            module_function

            # ~10 fps matches the reader/menu idle poll interval (0.1s), so the
            # glyph advances roughly one frame per redraw while work is in flight.
            FRAME_SECONDS = 0.1

            BRAILLE_FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze
            ASCII_FRAMES = %w[- \\ | /].freeze

            def ascii_icons?
              %w[1 true yes on].include?(ENV.fetch('SHOKO_ASCII_ICONS', '').to_s.strip.downcase)
            end

            def frames
              ascii_icons? ? ASCII_FRAMES : BRAILLE_FRAMES
            end

            # Current spinner glyph for the given monotonic timestamp.
            def glyph(now = monotonic_now)
              set = frames
              index = (now / FRAME_SECONDS).floor % set.length
              set[index]
            end

            def monotonic_now
              Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end
          end
        end
      end
    end
  end
end
