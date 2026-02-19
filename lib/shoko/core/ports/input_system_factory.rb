# frozen_string_literal: true

require_relative '../../application/ports/input_system_factory'

warn '[DEPRECATION] Shoko::Core::Ports::InputSystemFactory is deprecated; use Shoko::Application::Ports::InputSystemFactory'

module Shoko
  module Core
    module Ports
      module InputSystemFactory
        include Shoko::Application::Ports::InputSystemFactory
      end
    end
  end
end
