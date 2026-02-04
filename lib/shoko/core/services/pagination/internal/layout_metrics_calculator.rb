# frozen_string_literal: true

require_relative '../../pagination'
require_relative '../../layout_service'
require_relative '../../../ports/config_reader'
require_relative '../../../ports/ui_state_reader'

module Shoko
  module Core
    module Services
      module Pagination
        module Internal
          # Responsible for deriving layout metrics (column width, content height,
          # lines per page) from terminal dimensions and user configuration.
          #
          # This class follows hexagonal architecture principles:
          # - Config reading goes through ConfigReader port
          # - UI state reading goes through UIStateReader port
          class LayoutMetricsCalculator
            # @param config_reader [Core::Ports::ConfigReader] Port for reading config
            # @param ui_state_reader [Core::Ports::UIStateReader] Port for reading UI state
            # @param layout_service [LayoutService] Layout calculation service (required)
            def initialize(config_reader:, ui_state_reader:, layout_service:)
              raise ArgumentError, 'layout_service is required' unless layout_service

              @config_reader = config_reader
              @ui_state_reader = ui_state_reader
              @layout_service = layout_service
            end

            # Calculate layout metrics for given dimensions
            # @param width [Integer] Terminal width
            # @param height [Integer] Terminal height
            def layout(width, height)
              view_mode = @config_reader.view_mode
              @layout_service.calculate_metrics(width, height, view_mode)
            end

            def lines_per_page
              width = @ui_state_reader.terminal_width || 80
              height = @ui_state_reader.terminal_height || 24
              view_mode = @config_reader.view_mode || :single
              _, content = @layout_service.calculate_metrics(width, height, view_mode)
              spacing = @config_reader.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
              @layout_service.adjust_for_line_spacing(content, spacing)
            end

            # Calculate lines per page for given content height
            # @param content_height [Integer] Content area height
            def lines_per_page_for(content_height)
              spacing = @config_reader.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
              @layout_service.adjust_for_line_spacing(content_height, spacing)
            end

            def column_width_from_state
              width = @ui_state_reader.terminal_width || 80
              view_mode = @config_reader.view_mode || :single
              if view_mode == :split
                @layout_service.split_column_width(width)
              else
                @layout_service.single_column_width(width)
              end
            end

            private

            def content_height(height)
              @layout_service.content_area_height(height)
            end
          end
        end
      end
    end
  end
end
