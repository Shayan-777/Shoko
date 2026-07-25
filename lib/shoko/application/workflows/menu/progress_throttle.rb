# frozen_string_literal: true

module Shoko
  module Application
    module Workflows
      module Menu
        # Rate-limits progress notifications so a long download or install
        # publishes visible steps instead of every fractional tick.
        #
        # The dictionary, download, and translator-pack workflows all drive the
        # same progress presenters and shared the same threshold by copy; one
        # definition keeps their pacing identical.
        module ProgressThrottle
          MIN_PROGRESS_DELTA = 0.01

          module_function

          # @param progress [Float] 0.0..1.0
          # @param last_progress [Float, nil] last published value
          # @return [Boolean] true for the first tick, completion, or a step
          #   at least MIN_PROGRESS_DELTA away from the last published value
          def publish?(progress, last_progress)
            return true if last_progress.nil?
            return true if progress >= 1.0

            (progress - last_progress).abs >= MIN_PROGRESS_DELTA
          end
        end
      end
    end
  end
end
