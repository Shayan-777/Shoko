# frozen_string_literal: true

require_relative '../../application/ports/ui_state_reader'

warn '[DEPRECATION] Shoko::Core::Ports::UIStateReader is deprecated; use Shoko::Application::Ports::UiStateReader'

module Shoko
  module Core
    module Ports
      module UIStateReader
        include Shoko::Application::Ports::UiStateReader
      end
    end
  end
end
