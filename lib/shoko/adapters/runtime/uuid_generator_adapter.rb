# frozen_string_literal: true

require 'securerandom'
require_relative '../../application/ports/outbound/id_generator'

module Shoko
  module Adapters
    module Runtime
      # Port adapter for UUID generation.
      class UuidGeneratorAdapter
        include Shoko::Application::Ports::Outbound::IdGenerator

        def uuid
          SecureRandom.uuid
        end
      end
    end
  end
end
