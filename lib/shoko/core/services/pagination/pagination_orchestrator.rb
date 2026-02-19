# frozen_string_literal: true

require_relative '../../../application/services/pagination/pagination_orchestrator'

module Shoko
  module Core
    module Services
      module Pagination
        # @deprecated Use Shoko::Application::Services::Pagination::PaginationOrchestrator.
        class PaginationOrchestrator < Shoko::Application::Services::Pagination::PaginationOrchestrator
          def initialize(*args, logger: nil, **kwargs, &block)
            logger&.warn(
              'DEPRECATION: Core::Services::Pagination::PaginationOrchestrator is deprecated; ' \
              'use Application::Services::Pagination::PaginationOrchestrator'
            )
            super(*args, logger: logger, **kwargs, &block)
          end
        end
      end
    end
  end
end
