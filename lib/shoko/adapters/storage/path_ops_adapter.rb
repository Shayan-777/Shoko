# frozen_string_literal: true

require_relative '../../core/ports/path_ops'

module Shoko
  module Adapters
    module Storage
      # PathOps adapter backed by Ruby's File API.
      class PathOpsAdapter
        include Shoko::Core::Ports::PathOps

        def expand_path(path, dir = nil)
          dir ? File.expand_path(path, dir) : File.expand_path(path)
        end

        def join(*parts)
          File.join(*parts)
        end

        def basename(path)
          File.basename(path)
        end
      end
    end
  end
end
