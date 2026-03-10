# frozen_string_literal: true

require_relative '../../adapters/storage/book_cache_pipeline_factory_adapter'
require_relative 'domain_application_registration/domain_services'
require_relative 'domain_application_registration/output_services'
require_relative 'domain_application_registration/use_case_services'
require_relative 'domain_application_registration/document_loader_services'

module Shoko
  module Composition
    module ContainerFactory
      # Registers domain and application services in the DI container.
      module DomainApplicationRegistration
        include DomainServices
        include OutputServices
        include UseCaseServices
        include DocumentLoaderServices

        # Register application-level services and adapters.
        def register_application_services(container)
          register_output_services(container)
          register_use_case_services(container)
          register_document_loader(container)
        end
      end
    end
  end
end
