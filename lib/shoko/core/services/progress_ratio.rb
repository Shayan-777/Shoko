# frozen_string_literal: true

module Shoko
  module Core
    module Services
      # Normalizes progress metrics across menu and reader flows.
      module ProgressRatio
        module_function

        # Normalize partial progress against a total, guarding against zero denominators.
        #
        # @param done [Numeric]
        # @param total [Numeric]
        # @return [Float]
        def compute(done, total)
          denom = [total.to_f, 1.0].max
          done.to_f / denom
        end
      end
    end
  end
end
