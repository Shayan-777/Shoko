# frozen_string_literal: true

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

      def find_gemspec(name)
        @spec_cache ||= {}
        return @spec_cache[name] if @spec_cache.key?(name)

        spec = find_by_name(name) || find_in_paths(name, Gem.default_path) || find_in_paths(name, Gem.path)
        @spec_cache[name] = spec
      end

      def find_by_name(name)
        Gem::Specification.find_by_name(name)
      rescue Gem::LoadError, Gem::MissingSpecError
        nil
      rescue StandardError
        nil
      end
      private_class_method :find_by_name

      def find_in_paths(name, paths)
        gemspec = Array(paths).flat_map do |path|
          Dir.glob(File.join(path, 'specifications', "#{name}-*.gemspec"))
        end.max
        gemspec ? Gem::Specification.load(gemspec) : nil
      rescue StandardError
        nil
      end
      private_class_method :find_in_paths
    end
  end
end
