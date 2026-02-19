# frozen_string_literal: true

require_relative '../../../application/services/pagination/page_info_calculator'

module Shoko
  module Core
    module Services
      module Pagination
        # @deprecated Use Shoko::Application::Services::Pagination::PageInfoCalculator.
        class PageInfoCalculator < Shoko::Application::Services::Pagination::PageInfoCalculator
        end
      end
    end
  end
end
