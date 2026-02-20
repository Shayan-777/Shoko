# frozen_string_literal: true

require_relative '../../core/ports/outbound/dictionary_availability'

module Shoko
  module Adapters::Storage
    # Adapter implementing the DictionaryAvailability port.
    # Backend detection is injected to avoid coupling to a specific adapter.
    class DictionaryAvailabilityAdapter
      include Core::Ports::Outbound::DictionaryAvailability

      def initialize(backend_class:)
        @backend_class = backend_class
      end

      def sqlite3_available?
        @backend_class.sqlite3_available?
      end
    end
  end
end
