# frozen_string_literal: true

module Shoko
  module Core
    module Services
      # Derives a single book's status within an in-flight library pre-pagination
      # batch from the shared progress fields (the ordered processing list, the
      # completed count, and whether a batch is running). Pure and layer-agnostic so
      # both the library renderer and the open-gate share one definition of what
      # "ready", "recalculating", and "queued" mean — keyed by the book's source
      # path, which both sides have.
      module PrepaginationStatus
        READY = :ready              # not in an active batch → open normally
        DONE = :done                # already recalculated → open normally
        IN_PROGRESS = :in_progress  # currently recalculating → not yet openable
        QUEUED = :queued            # waiting its turn → not yet openable

        module_function

        def for_path(path, paths:, done:, active:)
          return READY unless active
          return READY if path.nil?

          index = Array(paths).index(path)
          return READY if index.nil?

          done_count = done.to_i
          return DONE if index < done_count
          return IN_PROGRESS if index == done_count

          QUEUED
        end

        # A finished or never-batched book opens normally; one still being or waiting
        # to be recalculated does not.
        def openable?(status)
          [READY, DONE].include?(status)
        end

        def pending?(status)
          [IN_PROGRESS, QUEUED].include?(status)
        end
      end
    end
  end
end
