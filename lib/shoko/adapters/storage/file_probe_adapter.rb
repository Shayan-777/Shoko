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

        # ISO 8601 timestamp string, or nil if the file is missing.
        # SystemCallError (missing/unreadable file) translates to nil here
        # because the adapter is the layer where filesystem exceptions
        # belong; the application sees a typed value, not a raw OS error.
        def mtime(path)
          File.mtime(path).iso8601
        rescue SystemCallError
          nil
        end
      end
    end
  end
end
