# frozen_string_literal: true

require_relative 'null_logger'

module Shoko
  module Core
    module Services
      # Error raised when a required dependency is not available.
      class DependencyError < StandardError; end

      # Base class for all domain services with dependency injection support.
      # Provides standardized initialization and dependency management.
      #
      # ## Dependency Resolution Patterns
      #
      # Use `resolve(name)` for REQUIRED dependencies - raises if not registered.
      # Use `resolve_optional(name)` for OPTIONAL dependencies - returns nil if not registered.
      #
      # @example Required vs Optional Dependencies
      #   def setup_service_dependencies
      #     @state_store = resolve(:state_store)           # Required - raises if missing
      #     @cache = resolve_optional(:pagination_cache)   # Optional - nil if missing
      #   end
      class BaseService
        attr_reader :dependencies

        def initialize(dependencies)
          @dependencies = dependencies
          @logger = resolve_logger
          validate_dependencies
          setup_service_dependencies
        end

        protected

        # Override in subclasses to specify required dependencies.
        # These will be validated during initialization.
        #
        # @return [Array<Symbol>] List of required dependency names
        def required_dependencies
          []
        end

        # Override in subclasses to setup specific service dependencies.
        # Called after validation, safe to use resolve() for required deps.
        def setup_service_dependencies
          # Default implementation does nothing
        end

        # Resolve a REQUIRED dependency from the container.
        # Raises DependencyError if the dependency is not registered.
        #
        # @param dependency_name [Symbol] The dependency to resolve
        # @return [Object] The resolved dependency
        # @raise [DependencyError] If dependency is not registered
        def resolve(dependency_name)
          raise DependencyError, 'Dependencies container does not support resolve' unless container_supports_resolve?

          raise DependencyError, "Dependency '#{dependency_name}' not registered" unless registered?(dependency_name)

          @dependencies.resolve(dependency_name)
        end

        # Resolve an OPTIONAL dependency from the container.
        # Returns nil if the dependency is not registered or resolution fails.
        #
        # @param dependency_name [Symbol] The dependency to resolve
        # @return [Object, nil] The resolved dependency, or nil if not available
        def resolve_optional(dependency_name)
          return nil unless container_supports_resolve?
          return nil unless registered?(dependency_name)

          @dependencies.resolve(dependency_name)
        rescue StandardError
          nil
        end

        # Alias for resolve_optional - provides backward compatibility.
        alias safe_resolve resolve_optional

        # Check if a dependency is registered in the container.
        #
        # @param dependency_name [Symbol] The dependency to check
        # @return [Boolean] True if registered
        def registered?(dependency_name)
          return false unless @dependencies.respond_to?(:registered?)

          @dependencies.registered?(dependency_name)
        end

        # Logger accessor - returns injected logger or null logger.
        # Logger is special-cased because it's needed for bootstrapping.
        def logger
          @logger ||= resolve_logger
        end

        private

        def container_supports_resolve?
          @dependencies.respond_to?(:resolve)
        end

        def validate_dependencies
          return unless respond_to?(:required_dependencies)

          missing = required_dependencies.reject { |dep| registered?(dep) }
          return if missing.empty?

          raise ArgumentError, "Missing required dependencies: #{missing.join(', ')}"
        end

        def resolve_logger
          return @dependencies.resolve(:logger) if registered?(:logger)

          NullLogger.new
        rescue StandardError
          NullLogger.new
        end
      end
    end
  end
end

module Shoko
  BaseService = Core::Services::BaseService
end
