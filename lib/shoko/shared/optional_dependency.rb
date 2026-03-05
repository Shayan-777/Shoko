# frozen_string_literal: true

require_relative 'errors'

module Shoko
  module Shared
    # Helper for optional gem dependencies without bundler lock-in.
    module OptionalDependency
      module_function

      def gem_available?(name)
        !find_gemspec(name).nil?
      end

      def add_gem_load_path(name)
        spec = find_gemspec(name)
        return nil unless spec

        lib_path = File.join(spec.full_gem_path, 'lib')
        $LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)
        spec
      end

      def require_gem!(name)
        Kernel.require(name)
        true
      rescue LoadError
        spec = add_gem_load_path(name)
        Kernel.require(name)
        true
      rescue LoadError => e
        message = if spec
                    "Failed to load optional gem '#{name}' from '#{spec.full_gem_path}': #{e.message}"
                  else
                    "Required optional gem '#{name}' is not installed: #{e.message}"
                  end
        raise Shoko::DependencyUnavailableError, message
      rescue Shoko::Error => e
        raise Shoko::DependencyUnavailableError, "Failed to load optional gem '#{name}': #{e.message}"
      end

      def find_gemspec(name)
        @spec_cache ||= {}
        return @spec_cache[name] if @spec_cache.key?(name)

        spec = find_by_name(name) || find_in_paths(name, Gem.default_path) || find_in_paths(name, Gem.path)
        @spec_cache[name] = spec
      end

      def find_by_name(name)
        Gem::Specification.find_by_name(name)
      end
      private_class_method :find_by_name

      def find_in_paths(name, paths)
        gemspec = Array(paths).flat_map do |path|
          Dir.glob(File.join(path, 'specifications', "#{name}-*.gemspec"))
        end.max
        gemspec ? Gem::Specification.load(gemspec) : nil
      end
      private_class_method :find_in_paths
    end
  end
end
