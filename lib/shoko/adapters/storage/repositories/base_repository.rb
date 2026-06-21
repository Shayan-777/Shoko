# frozen_string_literal: true

require 'shoko/shared/errors'

module Shoko
  module Adapters
    module Storage
      module Repositories
        # Base class for all repository implementations in the domain layer.
        #
        # Repositories provide an abstraction layer between domain services and
        # infrastructure storage mechanisms, following the Repository pattern from
        # Domain-Driven Design.
        #
        # All repositories should:
        # - Provide domain-focused methods (not storage-focused)
        # - Return domain objects or primitives
        # - Handle storage-specific errors and convert to domain errors
        # - Use dependency injection for storage implementations
        #
        # @example Implementing a repository
        #   class MyRepository < BaseRepository
        #     def find_by_id(id)
        #       storage_result = @storage.find(id)
        #       convert_to_domain_object(storage_result)
        #       # Handle Storage::NotFoundError and map to EntityNotFoundError.
        #     end
        #   end
        class BaseRepository
          # Repository-specific errors. Rooted at Shoko::Error so a translated
          # persistence failure (e.g. a disk-full StorageError re-raised as
          # PersistenceError by #handle_storage_error) stays inside the domain
          # error family: the `rescue Shoko::Error` boundaries above the repos
          # (StateController#save_progress, the menu workflows) are meant to
          # contain exactly these, and a bare StandardError subclass would slip
          # past every one of them and tear down the session.
          class RepositoryError < Shoko::Error; end
          class EntityNotFoundError < RepositoryError; end
          class ValidationError < RepositoryError; end
          class PersistenceError < RepositoryError; end

          def initialize(logger: nil)
            @logger = logger
          end

          protected

          attr_reader :logger

          # Helper to handle common storage errors
          def handle_storage_error(error, context = nil)
            msg = error.message
            message = context ? "#{context}: #{msg}" : msg
            logger&.error("Repository error - #{message}")

            case error
            when ArgumentError
              raise ValidationError, message
            else
              raise PersistenceError, message
            end
          end

          # Helper to validate required parameters
          def validate_required_params(params, required_keys)
            missing_keys = required_keys.select do |key|
              val = params[key]
              !params.key?(key) || val.nil? || blank_value?(val)
            end
            return if missing_keys.empty?

            raise ValidationError, "Missing required parameters: #{missing_keys.join(', ')}"
          end

          # Helper to ensure entity exists before operations
          def ensure_entity_exists(entity, entity_name = 'Entity')
            return if entity

            raise EntityNotFoundError, "#{entity_name} not found"
          end

          def blank_value?(value)
            case value
            when String, Array, Hash
              value.empty?
            else
              false
            end
          end
        end
      end
    end
  end
end
