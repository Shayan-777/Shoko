# frozen_string_literal: true

require 'set'

module Shoko
  module Bootstrap
      # Dependency injection container for managing service dependencies.
      class DependencyContainer
        class DependencyError < StandardError; end
        class CircularDependencyError < DependencyError; end

        def initialize
          @services = {}
          @factories = {}
          @singletons = {}
          @resolving = Set.new
        end

        # Register a singleton service
        #
        # @param name [Symbol] Service name
        # @param service [Object] Service instance
        def register(name, service)
          @services[name] = service
        end

        # Register a factory for lazy instantiation
        #
        # @param name [Symbol] Service name
        # @param factory [Proc] Factory proc that creates the service
        def register_factory(name, &factory)
          @factories[name] = factory
        end

        # Register a singleton factory
        #
        # @param name [Symbol] Service name
        # @param factory [Proc] Factory proc
        def register_singleton(name, &factory)
          @singletons[name] = factory
        end

        # Resolve a service by name
        #
        # @param name [Symbol] Service name
        # @return [Object] Service instance
        def resolve(name)
          return @services[name] if @services.key?(name)

          detect_circular_dependency(name) do
            resolve_from_factories(name)
          end
        end

        # Resolve multiple services
        #
        # @param names [Array<Symbol>] Service names
        # @return [Hash<Symbol, Object>] Hash of name => service
        def resolve_many(*names)
          names.to_h { |name| [name, resolve(name)] }
        end

        # Resolve a service by name, returning nil if not registered
        #
        # @param name [Symbol] Service name
        # @return [Object, nil] Service instance or nil
        def resolve_optional(name)
          return nil unless registered?(name)

          resolve(name)
        end

        # Remove a registered service instance
        #
        # @param name [Symbol] Service name
        def unregister(name)
          @services.delete(name)
        end

        # Check if service is registered
        #
        # @param name [Symbol] Service name
        # @return [Boolean]
        def registered?(name)
          @services.key?(name) || @factories.key?(name) || @singletons.key?(name)
        end

        # List all registered service names
        #
        # @return [Array<Symbol>]
        def service_names
          (@services.keys + @factories.keys + @singletons.keys).uniq
        end

        # Create child container with inherited services
        #
        # @return [DependencyContainer]
        def create_child
          child = self.class.new
          child.copy_registrations_from(self)
          child
        end

        # Clear all registrations (for testing)
        def clear!
          @services.clear
          @factories.clear
          @singletons.clear
        end

        # Copy registrations from another container
        # @api private
        def copy_registrations_from(source)
          @services = source.registry_services.dup
          @factories = source.registry_factories.dup
          @singletons = source.registry_singletons.dup
        end

        protected

        def registry_services = @services
        def registry_factories = @factories
        def registry_singletons = @singletons

        private

        def resolve_from_factories(name)
          if @singletons.key?(name)
            @services[name] ||= @singletons[name].call(self)
          elsif @factories.key?(name)
            @factories[name].call(self)
          else
            raise DependencyError, "Service '#{name}' not registered"
          end
        end

        def detect_circular_dependency(name)
          if @resolving.include?(name)
            raise CircularDependencyError,
                  "Circular dependency detected for '#{name}'"
          end

          @resolving.add(name)
          begin
            yield
          ensure
            @resolving.delete(name)
          end
        end
      end
  end
end
