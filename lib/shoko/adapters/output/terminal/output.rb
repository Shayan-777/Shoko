# frozen_string_literal: true

require 'io/console'

module Shoko
  module Adapters::Output::Terminal
    # TerminalOutput handles ANSI sequences and direct writes to an IO stream.
    class TerminalOutput
      attr_reader :io

      def initialize(io = $stdout)
        @io = io
      end

      # A collection of ANSI escape codes and helpers
      module ANSI
        RESET = "\e[0m"
        BOLD = "\e[1m"
        DIM = "\e[2m"
        ITALIC = "\e[3m"
        UNDERLINE = "\e[4m"
        REVERSE = "\e[7m"
        STRIKETHROUGH = "\e[9m"

        BLACK = "\e[30m"
        RED = "\e[31m"
        GREEN = "\e[32m"
        YELLOW = "\e[33m"
        BLUE = "\e[34m"
        MAGENTA = "\e[35m"
        CYAN = "\e[36m"
        WHITE = "\e[37m"
        GRAY = "\e[90m"
        LIGHT_GREY = "\e[37;1m"

        BRIGHT_RED = "\e[91m"
        BRIGHT_GREEN = "\e[92m"
        BRIGHT_YELLOW = "\e[93m"
        BRIGHT_BLUE = "\e[94m"
        BRIGHT_MAGENTA = "\e[95m"
        BRIGHT_CYAN = "\e[96m"
        BRIGHT_WHITE = "\e[97m"
        DEFAULT_FG = "\e[39m"

        BG_DARK = "\e[48;5;236m"
        BG_BLACK = "\e[40m"
        BG_BLUE = "\e[44m"
        BG_CYAN = "\e[46m"
        BG_GREY = "\e[48;5;240m"
        BG_SLATE = "\e[48;5;238m"
        BG_SOFT_GREEN = "\e[48;5;65m"
        BG_BRIGHT_GREEN = "\e[102m"
        BG_BRIGHT_YELLOW = "\e[103m"
        BG_BRIGHT_WHITE = "\e[107m"
        DEFAULT_BG = "\e[49m"

        module Control
          CLEAR = "\e[2J"
          HOME = "\e[H"
          HIDE_CURSOR = "\e[?25l"
          SHOW_CURSOR = "\e[?25h"
          SAVE_SCREEN = "\e[?1049h"
          RESTORE_SCREEN = "\e[?1049l"
        end

        def self.move(row, col)
          "\e[#{row};#{col}H"
        end

        def self.clear_line
          "\e[2K"
        end

        def self.clear_below
          "\e[J"
        end
      end

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
