# frozen_string_literal: true

module Shoko
  module Adapters
    module Support
      # Maps nested progress updates into a bounded parent progress range.
      class ProgressRangeReporter
        def initialize(reporter:, start_progress:, end_progress:)
          @reporter = reporter
          @start_progress = start_progress.to_f.clamp(0.0, 1.0)
          @end_progress = end_progress.to_f.clamp(0.0, 1.0)
        end

        def update_status(message: nil, progress: nil)
          return unless @reporter

          @reporter.update_status(message: message, progress: mapped_progress(progress))
        end

        private

        def mapped_progress(progress)
          return nil if progress.nil?

          normalized = progress.to_f.clamp(0.0, 1.0)
          @start_progress + ((@end_progress - @start_progress) * normalized)
        end
      end
    end
  end
end
