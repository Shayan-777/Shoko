# frozen_string_literal: true

require_relative '../../core/ports/file_probe'

module Shoko
  module Adapters
    module Storage
      # FileProbe adapter backed by Ruby's File API.
      class FileProbeAdapter
        include Shoko::Core::Ports::FileProbe

        def exist?(path)
          File.exist?(path)
        end

        def file?(path)
          File.file?(path)
        end

        def size(path)
          File.size(path)
        end
      end
    end
  end
end
