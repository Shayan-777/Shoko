# frozen_string_literal: true

require 'securerandom'
require_relative '../../core/ports/outbound/id_generator'

module Shoko
  module Adapters
    module Runtime
      # Port adapter for UUID generation.
      class UuidGeneratorAdapter
        include Shoko::Core::Ports::Outbound::IdGenerator

        def uuid
          SecureRandom.uuid
        end
      end
    end
  end
end
