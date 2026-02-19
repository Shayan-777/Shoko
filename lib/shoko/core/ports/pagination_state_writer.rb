# frozen_string_literal: true

require_relative '../../application/ports/pagination_state_writer'
require_relative '../../application/ports/ui_loading_writer'

warn '[DEPRECATION] Shoko::Core::Ports::PaginationStateWriter is deprecated; use Shoko::Application::Ports::PaginationStateWriter'

module Shoko
  module Core
    module Ports
      module PaginationStateWriter
        include Shoko::Application::Ports::PaginationStateWriter
        include Shoko::Application::Ports::UiLoadingWriter
      end
    end
  end
end
