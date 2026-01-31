# frozen_string_literal: true

require_relative 'null_logger'

module Shoko
  module Core
    module Services
      # Base class for all domain services.
      # Accepts dependencies via keyword constructor arguments — no container awareness.
      class BaseService
        def initialize(logger: nil)
          @logger = logger || NullLogger.new
        end

        protected

        attr_reader :logger
      end
    end
  end
end
