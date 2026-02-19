# frozen_string_literal: true

require_relative '../../../application/services/pagination/pagination_coordinator'

module Shoko
  module Core
    module Services
      module Pagination
        # @deprecated Use Shoko::Application::Services::Pagination::PaginationCoordinator.
        class PaginationCoordinator < Shoko::Application::Services::Pagination::PaginationCoordinator
          def initialize(*args, logger: nil, **kwargs, &block)
            logger&.warn(
              'DEPRECATION: Core::Services::Pagination::PaginationCoordinator is deprecated; ' \
              'use Application::Services::Pagination::PaginationCoordinator'
            )
            super(*args, logger: logger, **kwargs, &block)
          end
        end
      end
    end
  end
end
