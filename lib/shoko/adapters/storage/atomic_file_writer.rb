# frozen_string_literal: true

require 'fileutils'
require 'tempfile'

module Shoko
  module Adapters
    module Storage
      # Provides atomic, fsync-backed file writes to avoid partial/corrupt files.
      class AtomicFileWriter
        def self.write(path, data, binary: false)
          write_using(path, binary:) do |io|
            io.write(data)
          end
        end

        def self.write_using(path, binary: false)
          dir = File.dirname(path)
          FileUtils.mkdir_p(dir)
          tempfile = Tempfile.new(['shoko', File.basename(path)], dir)
          tempfile.binmode if binary
          yield(tempfile)
          tempfile.flush
          tempfile.fsync
          temp_path = tempfile.path
          tempfile.close
          File.rename(temp_path, path)
        ensure
          if tempfile
            begin
              tempfile.close unless tempfile.closed?
            rescue StandardError
              # ignore cleanup errors
            end
            begin
              tempfile.unlink if tempfile.path && File.exist?(tempfile.path)
            rescue StandardError
              # ignore cleanup errors
            end
          end
        end
      end
    end
  end
end
