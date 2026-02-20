# frozen_string_literal: true

require 'io/console'
require_relative '../../../shared/terminal/ansi'

module Shoko
  module Adapters::Output::Terminal
    # TerminalOutput handles ANSI sequences and direct writes to an IO stream.
    class TerminalOutput
      attr_reader :io

      def initialize(io = $stdout)
        @io = io
      end

      ANSI = Shoko::Shared::Terminal::Ansi

      def print(str)
        io.print(str)
      end

      def flush
        io.flush
      end

      def clear
        print(ANSI::Control::CLEAR + ANSI::Control::HOME)
        flush
      end

      def hide_cursor
        print(ANSI::Control::HIDE_CURSOR)
      end

      def show_cursor
        print(ANSI::Control::SHOW_CURSOR)
      end

      def save_screen
        print(ANSI::Control::SAVE_SCREEN)
      end

      def restore_screen
        print(ANSI::Control::RESTORE_SCREEN)
      end
    end
  end
end
