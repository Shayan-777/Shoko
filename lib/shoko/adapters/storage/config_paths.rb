# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      # Resolves XDG-aware configuration paths for Shoko.
      module ConfigPaths
        module_function

        # Root directory for Shoko config: ${XDG_CONFIG_HOME:-~/.config}/shoko
        def config_root
          env_home = ENV.fetch('XDG_CONFIG_HOME', nil)
          config_root = if env_home && !env_home.empty?
                          env_home
                        else
                          File.join(Dir.home, '.config')
                        end
          File.join(config_root, 'shoko')
        end

        # Downloaded books directory under config root.
        def downloads_root
          File.join(config_root, 'downloads')
        end

        def config_path(*segments)
          File.join(config_root, *segments)
        end
      end
    end
  end
end
