# frozen_string_literal: true

require_relative '../constants/ui_constants'

module Shoko
  module Adapters
    module Ui
      module Components
        # Base class for all UI components.
        # Provides mount lifecycle management and the rendering contract.
        #
        # Rendering is immediate-mode: every frame recomposes every visible
        # component from current state, and the terminal buffer diffs rows on
        # flush so unchanged output costs no terminal I/O. Components hold no
        # dirty flags — when a frame is needed off the input path, request it
        # through the reader controller's render-request flag, not here.
        class BaseComponent
          attr_reader :dependencies

          def initialize(dependencies = nil)
            @dependencies = dependencies
            @initialized = false
          end

          # Render this component into the given surface within bounds
          # @param surface [Surface] terminal surface wrapper
          # @param bounds [Rect] local bounds for this component
          def render(surface, bounds)
            ensure_mounted
            do_render(surface, bounds)
          end

          # Override this method in subclasses for actual rendering logic
          def do_render(surface, bounds)
            # to be implemented by subclasses
          end

          # Handle input key for this component
          # Return :handled or :pass_through
          def handle_input(_key)
            :pass_through
          end

          # Component height calculation contract
          # @param available_height [Integer] Total height available from parent
          # @return [Integer, :flexible, :fill] Height requirement:
          #   - Integer: Fixed height in rows
          #   - :flexible: Use as much space as needed, up to available
          #   - :fill: Take all remaining space after fixed components
          def preferred_height(_available_height)
            :flexible
          end

          # Component width calculation contract
          # @param available_width [Integer] Total width available from parent
          # @return [Integer, :flexible] Width requirement
          def preferred_width(_available_width)
            :flexible
          end

          # Component lifecycle methods

          # Called once when component is first initialized with a parent
          def mount
            ensure_mounted
          end

          # Called when component is removed from the component tree
          def unmount
            ensure_unmounted
          end

          # Override in subclasses for mount logic
          def on_mount
            # no-op by default
          end

          # Override in subclasses for cleanup logic
          def on_unmount
            # no-op by default
          end

          private

          def ensure_mounted
            return if @initialized

            on_mount
            @initialized = true
          end

          def ensure_unmounted
            return unless @initialized

            on_unmount
            @initialized = false
          end
        end
      end
    end
  end
end
