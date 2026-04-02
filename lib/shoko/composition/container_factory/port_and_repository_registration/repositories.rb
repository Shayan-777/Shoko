# frozen_string_literal: true

require_relative '../../../adapters/storage/repositories/bookmark_repository'
require_relative '../../../adapters/storage/repositories/annotation_repository'
require_relative '../../../adapters/storage/repositories/progress_repository'

module Shoko
  module Composition
    module ContainerFactory
      # Registers persistence adapters used by domain and application services.
      module PortAndRepositoryRegistrationRepositories
        def register_repositories(container)
          register_bookmark_repository(container)
          register_annotation_repository(container)
          register_progress_repository(container)
        end

        private

        def register_bookmark_repository(container)
          container.register_factory(:bookmark_repository) do |c|
            Shoko::Adapters::Storage::Repositories::BookmarkRepository.new(
              file_writer: c.resolve(:file_writer),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_annotation_repository(container)
          container.register_factory(:annotation_repository) do |c|
            Shoko::Adapters::Storage::Repositories::AnnotationRepository.new(
              file_writer: c.resolve(:file_writer),
              logger: c.resolve(:logger)
            )
          end
        end

        def register_progress_repository(container)
          container.register_factory(:progress_repository) do |c|
            Shoko::Adapters::Storage::Repositories::ProgressRepository.new(
              file_writer: c.resolve(:file_writer),
              logger: c.resolve(:logger)
            )
          end
        end
      end
    end
  end
end
