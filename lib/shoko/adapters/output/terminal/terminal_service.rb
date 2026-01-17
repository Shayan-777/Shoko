# frozen_string_literal: true

require_relative '../../../core/services/base_service'
require_relative '../ui/constants/ui_constants'

module Shoko
  module Adapters::Output::Terminal
    # Terminal interaction service for mouse and rendering coordination
    class TerminalService < BaseService
      # Maintain a global session depth so nested setup/cleanup calls
      # (e.g., menu -> reader) don't flicker or drop to shell.
      class << self
        attr_accessor :session_depth
      end
      @session_depth = 0

      def enable_mouse
        Terminal.enable_mouse
      end

      def disable_mouse
        Terminal.disable_mouse
      end

      def read_input_with_mouse(timeout: nil)
        Terminal.read_input_with_mouse(timeout: timeout)
      end

      def read_key
        Terminal.read_key
      end

      def size
        Terminal.size
      end

      def end_frame
        Terminal.end_frame
      end

      def setup
        previous_depth = TerminalService.session_depth || 0
        depth = previous_depth + 1
        TerminalService.session_depth = depth
        logger&.debug('terminal.setup', depth: depth)
        return if previous_depth.positive?

        Terminal.setup
        apply_color_mode
      rescue StandardError => e
        TerminalService.session_depth = previous_depth
        logger&.error('terminal.setup_failed', error: e.message)
        raise
      end

      def cleanup(force: false)
        return force_cleanup! if force

        depth = decrement_session_depth
        logger&.debug('terminal.cleanup', depth: depth)
        return if depth.positive?

        perform_terminal_cleanup
      rescue StandardError => e
        logger&.error('terminal.cleanup_failed', error: e.message)
        raise
      end

      # Ensure session depth is at least the expected value (for nested sessions)
      # This guards against depth getting out of sync
      def ensure_session_depth(minimum_depth)
        current = TerminalService.session_depth || 0
        return if current >= minimum_depth

        logger&.warn('terminal.depth_correction', current: current, expected: minimum_depth)
        TerminalService.session_depth = minimum_depth
      end

      def force_cleanup
        cleanup(force: true)
      end

      def start_frame(width: nil, height: nil)
        Terminal.start_frame(width: width, height: height)
      end

      def read_key_blocking(timeout: nil)
        Terminal.read_key_blocking(timeout: timeout)
      end

      # Read one blocking key, then drain a few non-blocking extras.
      # Returns an array of keys, or [] if nothing was read.
      #
      # @param limit [Integer] maximum total keys to return
      # @return [Array<String>]
      def read_keys_blocking(limit: 10, timeout: nil)
        first = read_key_blocking(timeout: timeout)
        return [] unless first

        keys = [first]
        while (extra = read_key)
          keys << extra
          break if keys.size >= limit
        end
        keys
      end

      # Create a surface for component rendering
      def create_surface
        Shoko::Adapters::Output::Ui::Components::Surface.new(Terminal)
      end

      protected

      def required_dependencies
        [] # No dependencies required
      end

      private

      def logger
        @logger ||= begin
          resolve(:logger)
        rescue StandardError
          nil
        end
      end

      def force_cleanup!
        depth = TerminalService.session_depth || 0
        logger&.warn('terminal.cleanup.force', depth: depth)
        TerminalService.session_depth = 0
        perform_terminal_cleanup
      end

      def decrement_session_depth
        depth = TerminalService.session_depth
        return 0 unless depth

        new_depth = depth.positive? ? depth - 1 : 0
        TerminalService.session_depth = new_depth
        new_depth
      end

      def perform_terminal_cleanup
        Terminal.cleanup
      end

      def apply_color_mode
        mode = Terminal.color_mode
        Shoko::Adapters::Output::Ui::Constants::UI.apply_color_mode(mode)
      rescue StandardError => e
        logger&.warn('terminal.color_mode_failed', error: e.message)
      end
    end
  end
end
