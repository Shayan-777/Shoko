# frozen_string_literal: true

module Shoko
  module Adapters
    module Translation
      # Resolves the shoko-translate engine binary. Search order: explicit
      # env override, the copy built inside the source tree, then PATH.
      module EngineLocator
        ENV_KEY = 'SHOKO_TRANSLATE_ENGINE'
        BINARY_NAME = 'shoko-translate'
        BUILD_HINT = 'make -C ext/shoko_translate'

        module_function

        def path
          override = ENV.fetch(ENV_KEY, '').strip
          return override unless override.empty?

          bundled = bundled_path
          return bundled if File.executable?(bundled)

          path_lookup
        end

        def available?
          resolved = path
          !resolved.nil? && File.executable?(resolved)
        end

        # ext/shoko_translate/shoko-translate relative to the repo/gem root.
        def bundled_path
          File.expand_path('../../../../ext/shoko_translate/shoko-translate', __dir__)
        end

        def build_dir
          File.dirname(bundled_path)
        end

        def path_lookup
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |dir|
            candidate = File.join(dir, BINARY_NAME)
            return candidate if File.executable?(candidate)
          end
          nil
        end
      end
    end
  end
end
