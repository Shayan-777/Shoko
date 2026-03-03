# frozen_string_literal: true

require_relative 'nav_context'
require_relative 'context_helpers'

module Shoko
  module Application
    module Services
      module Reader
        module Navigation
          # Builds navigation context snapshots from the current state.
          # Uses hexagonal ports for reading state - no direct state_store access.
          class ContextBuilder
            # Construct with required ports
            # @param config_reader [Core::Ports::Outbound::ConfigReader] Port for reading config
            # @param reader_state_reader [Core::Ports::Outbound::ReaderNavigationReader] Port for reading reader state
            # @param page_calculator [Object] Page calculator service (optional)
            def initialize(config_reader:, reader_state_reader:, page_calculator: nil)
              @config_reader = config_reader
              @reader_state_reader = reader_state_reader
              @page_calculator = page_calculator
            end

            # Factory method for port-based construction (alias for constructor)
            # @param config_reader [Core::Ports::Outbound::ConfigReader] Port for reading config
            # @param reader_state_reader [Core::Ports::Outbound::ReaderNavigationReader] Port for reading reader state
            # @param page_calculator [Object] Page calculator service
            def self.with_ports(config_reader:, reader_state_reader:, page_calculator: nil)
              new(config_reader: config_reader, reader_state_reader: reader_state_reader,
                  page_calculator: page_calculator)
            end

            def build
              snapshot = build_snapshot
              build_context_from_snapshot(snapshot)
            end

            private

            attr_reader :page_calculator, :config_reader, :reader_state_reader

            def build_snapshot
              ContextHelpers.build_snapshot_from_ports(
                config_reader: config_reader,
                reader_state_reader: reader_state_reader
              )
            end

            def build_context_from_snapshot(snapshot)
              NavContext.new(
                mode: ContextHelpers.dynamic_mode?(snapshot) ? :dynamic : :absolute,
                view_mode: ContextHelpers.current_view_mode(snapshot),
                current_chapter: ContextHelpers.current_chapter(snapshot),
                total_chapters: ContextHelpers.total_chapters(snapshot),
                current_page_index: ContextHelpers.current_page_index(snapshot),
                dynamic_total_pages: dynamic_total_pages,
                single_page: ContextHelpers.single_page(snapshot),
                left_page: ContextHelpers.left_page(snapshot),
                right_page: ContextHelpers.right_page(snapshot),
                max_page_in_chapter: 0,
                lines_per_page: 0,
                column_lines_per_page: 0,
                max_offset_in_chapter: 0
              )
            end

            def dynamic_total_pages
              return 0 unless page_calculator

              page_calculator.total_pages.to_i
            end
          end
        end
      end
    end
  end
end
