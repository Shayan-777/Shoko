# frozen_string_literal: true

module Shoko
  module Adapters::Ui::Components
    # Base class for all UI components.
    # Provides lifecycle management, rendering contract, and observer support.
    class BaseComponent
      attr_reader :dependencies

      def initialize(dependencies = nil)
        @dependencies = dependencies
        @initialized = false
        @needs_update = true
      end

      # Render this component into the given surface within bounds
      # @param surface [Surface] terminal surface wrapper
      # @param bounds [Rect] local bounds for this component
      def render(surface, bounds)
        ensure_mounted

        # Always render for now to debug display issues
        do_render(surface, bounds)
        mark_updated
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

      # Mark component as needing a re-render
      def invalidate
        @needs_update = true
      end

      # Check if component needs to be re-rendered
      def needs_update?
        @needs_update
      end

      # Mark component as updated (called automatically after render)
      def mark_updated
        @needs_update = false
      end

      # Override in subclasses for mount logic
      def on_mount
        # no-op by default
      end

      # Override in subclasses for cleanup logic
      def on_unmount
        # no-op by default
      end

      # Observer pattern support for state changes
      def state_changed(_path, _old_value, _new_value)
        invalidate
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
