# frozen_string_literal: true

require 'shoko/shared/terminal/text_metrics'

module Shoko
  module Adapters
    module Output
      module Terminal
        # Output adapter wrapper around shared terminal text metrics primitives.
        TextMetrics = Shoko::Shared::Terminal::TextMetrics
      end
    end
  end
end
