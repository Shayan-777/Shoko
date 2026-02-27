# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      # Cache path helpers (XDG-compatible) for on-disk Shoko artifacts.
      module CachePaths
        module_function

        # Root directory for Shoko cache: ${XDG_CACHE_HOME:-~/.cache}/shoko
        def cache_root
          env_home = ENV.fetch('XDG_CACHE_HOME', nil)
          cache_root = if env_home && !env_home.empty?
                         env_home
                       else
                         File.join(Dir.home, '.cache')
                       end
          File.join(cache_root, 'shoko')
        end
      end
    end
  end
end
