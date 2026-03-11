# frozen_string_literal: true

module Shoko
  module Composition
    module ContainerFactory
      module DomainApplicationRegistration
        # Use-case and workflow service registration.
        module UseCaseServices
          def register_use_case_services(container)
            register_catalog_service(container)
            register_download_service(container)
            register_settings_service(container)
            register_pagination_cache_preloader(container)
          end

          private

          def register_catalog_service(container)
            container.register_factory(:catalog_service) do |c|
              Shoko::Application::UseCases::CatalogService.new(
                library_scanner: c.resolve(:library_scanner),
                metadata_reader: c.resolve(:metadata_reader),
                cached_library_repository: c.resolve(:cached_library_repository),
                recent_files_repository: c.resolve(:recent_files_repository),
                logger: c.resolve(:logger),
                file_probe: c.resolve(:file_probe)
              )
            end
          end

          def register_download_service(container)
            container.register_factory(:download_service) do |c|
              config_storage = c.resolve(:config_storage)
              downloads = config_storage ? File.join(config_storage.config_dir, 'downloads') : nil
              Shoko::Adapters::BookSources::DownloadService.new(
                gutendex_client: c.resolve(:gutendex_client),
                libgen_client: c.resolve(:libgen_client),
                downloads_root: downloads,
                logger: c.resolve(:logger)
              )
            end
          end

          def register_settings_service(container)
            container.register_factory(:settings_service) do |c|
              Shoko::Application::UseCases::SettingsService.new(**settings_service_dependencies(c))
            end
          end

          def settings_service_dependencies(container)
            {
              app_config_store: container.resolve(:app_config_store),
              cache_manager: container.resolve(:cache_manager),
              dictionary_availability: container.resolve(:dictionary_availability),
              dictionary_storage: container.resolve(:dictionary_storage),
              data_cleanup: container.resolve(:data_cleanup),
              wrapping_service: container.resolve(:wrapping_service),
              recent_files_repository: container.resolve(:recent_files_repository),
              dictionary_service: container.resolve(:dictionary_service),
              catalog_service: container.resolve(:catalog_service),
              config_storage: container.resolve(:config_storage),
              logger: container.resolve(:logger),
            }
          end

          def register_pagination_cache_preloader(container)
            container.register_factory(:pagination_cache_preloader) do |c|
              Shoko::Application::Services::Pagination::PaginationCachePreloader.new(
                page_calculator: c.resolve(:page_calculator),
                pagination_cache: c.resolve(:pagination_cache),
                app_config_store: c.resolve(:app_config_store),
                reader_session_store: c.resolve(:reader_session_store),
                reader_runtime_context: c.resolve(:reader_runtime_context),
                logger: c.resolve(:logger)
              )
            end
          end
        end
      end
    end
  end
end
