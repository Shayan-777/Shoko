# frozen_string_literal: true

require_relative '../../adapters/output/terminal/terminal'

module Shoko
  module Shared
    module Terminal
      # Shared terminal device primitive used by UI/output adapters.
      Device = Shoko::Adapters::Output::Terminal::Terminal
    end
  end
end
