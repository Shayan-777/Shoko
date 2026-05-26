# frozen_string_literal: true

require_relative '../../application/ports/outbound/file_probe'

module Shoko
  module Adapters
    module Storage
      # FileProbe adapter backed by Ruby's File API.
      class FileProbeAdapter
        include Shoko::Application::Ports::Outbound::FileProbe

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
