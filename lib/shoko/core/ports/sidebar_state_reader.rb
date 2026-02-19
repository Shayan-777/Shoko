# frozen_string_literal: true

require_relative '../../application/ports/sidebar_state_reader'

warn '[DEPRECATION] Shoko::Core::Ports::SidebarStateReader is deprecated; use Shoko::Application::Ports::SidebarStateReader'

module Shoko
  module Core
    module Ports
      module SidebarStateReader
        include Shoko::Application::Ports::SidebarStateReader
      end
    end
  end
end
