# frozen_string_literal: true

module Shoko
  module Bootstrap
    # Session-scoped mutable references used across reader/menu orchestration.
    # This replaces runtime DI container mutation for session objects.
    class ReaderSessionContext
      attr_accessor :document, :background_worker
    end
  end
end
