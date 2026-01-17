# frozen_string_literal: true

require_relative '../../pagination'
require_relative '../../layout_service'
require_relative '../../../ports/config_reader'

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
          class LayoutMetricsCalculator
            def initialize(state_store, layout_service: nil)
              @state_store = state_store
              @layout_service = layout_service || Shoko::Core::Services::LayoutService.new(nil)
            end

            # Calculate layout metrics for given dimensions
            # @param width [Integer] Terminal width
            # @param height [Integer] Terminal height
            # @param config [Object] ConfigReader port, state store, or state hash
            def layout(width, height, config)
              view_mode = extract_view_mode(config)
              @layout_service.calculate_metrics(width, height, view_mode)
            end

            def lines_per_page
              state = current_state
              width = state.dig(:ui, :terminal_width) || 80
              height = state.dig(:ui, :terminal_height) || 24
              view_mode = resolve_view_mode(state)
              _, content = @layout_service.calculate_metrics(width, height, view_mode)
              spacing = state.dig(:config, :line_spacing) || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
              @layout_service.adjust_for_line_spacing(content, spacing)
            end

            # Calculate lines per page for given content height
            # @param content_height [Integer] Content area height
            # @param config [Object] ConfigReader port, state store, or state hash
            def lines_per_page_for(content_height, config)
              spacing = extract_line_spacing(config)
              @layout_service.adjust_for_line_spacing(content_height,
                                                      spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING)
            end

            def column_width_from_state
              state = current_state
              width = state.dig(:ui, :terminal_width) || 80
              column_width(width, state)
            end

            private

            def current_state
              @state_store.current_state
            end

            # Extract view_mode from various config types (ConfigReader, state store, or hash)
            def extract_view_mode(config)
              if config.respond_to?(:view_mode)
                config.view_mode
              elsif config.respond_to?(:get)
                config.get(%i[config view_mode])
              elsif config.respond_to?(:dig)
                config.dig(:config, :view_mode)
              end || :split
            end

            # Extract line_spacing from various config types (ConfigReader, state store, or hash)
            def extract_line_spacing(config)
              if config.respond_to?(:line_spacing)
                config.line_spacing
              elsif config.respond_to?(:get)
                config.get(%i[config line_spacing])
              elsif config.respond_to?(:dig)
                config.dig(:config, :line_spacing)
              end
            end

            def column_width(width, config)
              view_mode = extract_view_mode(config)
              if view_mode == :split
                @layout_service.split_column_width(width)
              else
                @layout_service.single_column_width(width)
              end
            end

            def content_height(height)
              @layout_service.content_area_height(height)
            end

            def resolve_view_mode(state_hash)
              state_hash.dig(:config, :view_mode) || :split
            end
          end
        end
      end
    end
  end
end
