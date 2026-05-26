# frozen_string_literal: true

require_relative '../../application/ports/outbound/path_ops'

module Shoko
  module Adapters
    module Storage
      # PathOps adapter backed by Ruby's File API.
      class PathOpsAdapter
        include Shoko::Application::Ports::Outbound::PathOps

        def expand_path(path, dir = nil)
          dir ? File.expand_path(path, dir) : File.expand_path(path)
        end

        def join(*parts)
          File.join(*parts)
        end

        def basename(path)
          File.basename(path)
        end

        def extname(path)
          File.extname(path)
        end
      end
    end
  end
end
