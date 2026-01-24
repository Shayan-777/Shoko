# frozen_string_literal: true

module Shoko
  module Adapters::Storage::Repositories
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
    #     rescue Storage::NotFoundError => e
    #       raise EntityNotFoundError, e.message
    #     end
    #   end
    class BaseRepository
      # Repository-specific errors
      class RepositoryError < StandardError; end
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
        logger.error("Repository error - #{message}")

        case error
        when NoMethodError, ArgumentError
          raise ValidationError, message
        else
          raise PersistenceError, message
        end
      end

      # Helper to validate required parameters
      def validate_required_params(params, required_keys)
        missing_keys = required_keys.select do |key|
          val = params[key]
          !params.key?(key) || val.nil? || (val.respond_to?(:empty?) && val.empty?)
        end
        return if missing_keys.empty?

        raise ValidationError, "Missing required parameters: #{missing_keys.join(', ')}"
      end

      # Helper to ensure entity exists before operations
      def ensure_entity_exists(entity, entity_name = 'Entity')
        return if entity

        raise EntityNotFoundError, "#{entity_name} not found"
      end
    end
  end
end
