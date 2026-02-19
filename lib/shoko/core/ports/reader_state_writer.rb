# frozen_string_literal: true

require_relative '../../application/ports/reader_state_writer'

warn '[DEPRECATION] Shoko::Core::Ports::ReaderStateWriter is deprecated; use Shoko::Application::Ports::ReaderStateWriter'

module Shoko
  module Core
    module Ports
      module ReaderStateWriter
        include Shoko::Application::Ports::ReaderStateWriter
      end
    end
  end
end
