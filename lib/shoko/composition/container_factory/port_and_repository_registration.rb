# frozen_string_literal: true

require_relative 'port_and_repository_registration/terminal_ports'
require_relative 'port_and_repository_registration/book_source_ports'
require_relative 'port_and_repository_registration/dictionary_and_translation_ports'
require_relative 'port_and_repository_registration/storage_ports'
require_relative 'port_and_repository_registration/archive_ports'
require_relative 'port_and_repository_registration/ui_factory_ports'
require_relative 'port_and_repository_registration/repositories'
require_relative 'port_and_repository_registration/state_management'
require_relative 'port_and_repository_registration/ui_state_adapters'
require_relative 'port_and_repository_registration/library_services'

module Shoko
  module Composition
    module ContainerFactory
      # Registers ports, adapters, and repositories in the DI container.
      module PortAndRepositoryRegistration
        include PortAndRepositoryRegistrationTerminalPorts
        include PortAndRepositoryRegistrationBookSourcePorts
        include PortAndRepositoryRegistrationDictionaryAndTranslationPorts
        include PortAndRepositoryRegistrationStoragePorts
        include PortAndRepositoryRegistrationArchivePorts
        include PortAndRepositoryRegistrationUiFactoryPorts
        include PortAndRepositoryRegistrationRepositories
        include PortAndRepositoryRegistrationStateManagement
        include PortAndRepositoryRegistrationUiStateAdapters
        include PortAndRepositoryRegistrationLibraryServices

        # Registers the shared adapter ports used across runtime composition.
        def register_core_ports(container)
          register_terminal_ports(container)
          register_book_source_ports(container)
          register_dictionary_ports(container)
          register_translation_ports(container)
          register_storage_ports(container)
          register_archive_ports(container)
          register_ui_factory_ports(container)
        end
      end
    end
  end
end
