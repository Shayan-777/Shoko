# frozen_string_literal: true

module Shoko
  module Core
    module Events
      # Builds domain events with injected metadata providers.
      class EventFactory
        def initialize(wall_clock:, id_generator:)
          @wall_clock = wall_clock
          @id_generator = id_generator
        end

        def build(event_class, **attributes)
          event_class.new(
            event_id: @id_generator.uuid,
            occurred_at: @wall_clock.utc_now,
            **attributes
          )
        end
      end
    end
  end
end
