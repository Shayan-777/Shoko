# frozen_string_literal: true

module Shoko
  module Adapters
    module Ui
      module Builders
        # Builder for page setup configuration
        class PageSetupBuilder
          attr_reader :setup

          def initialize
            @setup = PageSetup.new
          end

          def with_lines(lines)
            @setup.lines = lines
            self
          end

          def with_wrapped(wrapped)
            @setup.wrapped = wrapped
            self
          end

          def with_dimensions(col_width, content_height, displayable_lines)
            @setup.col_width = col_width
            @setup.content_height = content_height
            @setup.displayable_lines = displayable_lines
            self
          end

          def with_position(col_start)
            @setup.col_start = col_start
            self
          end

          def build
            @setup
          end
        end

        # Data structure representing page setup parameters
        PageSetup = Struct.new(
          :lines, :wrapped, :col_width, :col_start,
          :content_height, :displayable_lines,
          keyword_init: true
        )
      end
    end
  end
end
