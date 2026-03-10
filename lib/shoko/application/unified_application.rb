# frozen_string_literal: true

module Shoko
  module Application
    # Unified application entry point that handles both file and menu scenarios
    class UnifiedApplication
      Dependencies = Data.define(:app_mode_runner)

      def initialize(epub_path = nil, deps:)
        raise ArgumentError, 'UnifiedApplication dependencies are required' if deps.nil?

        @epub_path = epub_path
        @deps = deps
      end

      def run
        if @epub_path
          reader_mode
        else
          menu_mode
        end
      end

      private

      def reader_mode
        deps.app_mode_runner.run_reader(path: @epub_path)
      end

      def menu_mode
        deps.app_mode_runner.run_menu
      end

      attr_reader :deps
    end
  end
end
