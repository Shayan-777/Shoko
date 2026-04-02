# frozen_string_literal: true

require_relative '../../../adapters/storage/dictionary_availability_adapter'
require_relative '../../../adapters/storage/dictionary_storage_adapter'
require_relative '../../../adapters/translation/libre_translate_adapter'

module Shoko
  module Composition
    module ContainerFactory
      # Registers dictionary and translation ports for composition wiring.
      module PortAndRepositoryRegistrationDictionaryAndTranslationPorts
        private

        def register_dictionary_ports(container)
          container.register_singleton(:dictionary_availability) do |_c|
            require_relative '../../../adapters/storage/sqlite_dictionary_adapter'

            Shoko::Adapters::Storage::DictionaryAvailabilityAdapter.new(
              backend_class: Shoko::Adapters::Storage::SqliteDictionaryAdapter
            )
          end
          container.register_singleton(:dictionary_storage) do |_c|
            Shoko::Adapters::Storage::DictionaryStorageAdapter.new
          end
        end

        def register_translation_ports(container)
          container.register_singleton(:translation_repository) do |c|
            Shoko::Adapters::Translation::LibreTranslateAdapter.new(logger: c.resolve(:logger))
          end
        end
      end
    end
  end
end
