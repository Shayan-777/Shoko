# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Port interface for rendering output.
      # Adapters implementing this interface should handle rendering
      # content to the terminal or other output targets.
      #
      # @example Implementing this port
      #   class TerminalRenderer
      #     include Shoko::Core::Ports::Renderer
      #
      #     def render(content, bounds)
      #       # Implementation
      #     end
      #   end
      module Renderer
        # Render content within specified bounds
        #
        # @param content [Object] Content to render
        # @param bounds [Object] Rendering bounds (x, y, width, height)
        # @return [void]
        def render(content, bounds)
          raise NotImplementedError, "#{self.class} must implement #render"
        end

        # Clear the render target
        #
        # @return [void]
        def clear
          raise NotImplementedError, "#{self.class} must implement #clear"
        end

        # Flush buffered output to the render target
        #
        # @return [void]
        def flush
          raise NotImplementedError, "#{self.class} must implement #flush"
        end

        # Get the dimensions of the render target
        #
        # @return [Array<Integer>] [width, height]
        def dimensions
          raise NotImplementedError, "#{self.class} must implement #dimensions"
        end

        # Write text at a specific position
        #
        # @param row [Integer] Row position
        # @param col [Integer] Column position
        # @param text [String] Text to write
        # @param style [Hash] Optional styling (color, bold, etc.)
        # @return [void]
        def write_at(row, col, text, style: {})
          raise NotImplementedError, "#{self.class} must implement #write_at"
        end

        # Draw a horizontal line
        #
        # @param row [Integer] Row position
        # @param col [Integer] Starting column
        # @param length [Integer] Line length
        # @param char [String] Character to use (default: '-')
        # @return [void]
        def draw_hline(row, col, length, char: '-')
          raise NotImplementedError, "#{self.class} must implement #draw_hline"
        end

        # Draw a vertical line
        #
        # @param row [Integer] Starting row
        # @param col [Integer] Column position
        # @param length [Integer] Line length
        # @param char [String] Character to use (default: '|')
        # @return [void]
        def draw_vline(row, col, length, char: '|')
          raise NotImplementedError, "#{self.class} must implement #draw_vline"
        end

        # Draw a box
        #
        # @param row [Integer] Top-left row
        # @param col [Integer] Top-left column
        # @param width [Integer] Box width
        # @param height [Integer] Box height
        # @return [void]
        def draw_box(row, col, width, height)
          raise NotImplementedError, "#{self.class} must implement #draw_box"
        end
      end
    end
  end
end
