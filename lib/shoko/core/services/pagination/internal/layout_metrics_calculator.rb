# frozen_string_literal: true

require_relative '../../pagination'
require_relative '../../layout_service'

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
          # - Layout dimensions are explicit method inputs
          class LayoutMetricsCalculator
            # @param config_reader [Application::Ports::ConfigReader] Port for reading config
            # @param layout_service [LayoutService] Layout calculation service (required)
            def initialize(config_reader:, layout_service:)
              raise ArgumentError, 'layout_service is required' unless layout_service

              @config_reader = config_reader
              @layout_service = layout_service
            end

            # Calculate layout metrics for given dimensions
            # @param width [Integer] Terminal width
            # @param height [Integer] Terminal height
            # @param sidebar_visible [Boolean, nil] Optional sidebar visibility override
            def layout(width, height, sidebar_visible: nil)
              width = dimension_or_default(width, 80)
              height = dimension_or_default(height, 24)
              view_mode = @config_reader.view_mode
              effective_width = @layout_service.effective_content_width(
                width,
                sidebar_visible: sidebar_visible == true
              )
              @layout_service.calculate_metrics(effective_width, height, view_mode)
            end

            # Calculate lines per page for given content height
            # @param content_height [Integer] Content area height
            def lines_per_page_for(content_height)
              spacing = @config_reader.line_spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
              @layout_service.adjust_for_line_spacing(content_height, spacing)
            end

            # Calculate lines per page for concrete terminal dimensions.
            def lines_per_page_for_dimensions(width:, height:, sidebar_visible: false)
              _, content_height = layout(width, height, sidebar_visible: sidebar_visible)
              lines_per_page_for(content_height)
            end

            private

            def dimension_or_default(value, fallback)
              parsed = value.to_i
              parsed.positive? ? parsed : fallback
            end
          end
        end
      end
    end
  end
end
