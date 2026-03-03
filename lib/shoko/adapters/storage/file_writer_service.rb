# frozen_string_literal: true

require 'fileutils'
require_relative '../base_adapter'

module Shoko
  module Adapters
    module Storage
      # Provides atomic file writing for domain repositories without coupling them
      # to infrastructure implementations.
      class FileWriterService < Shoko::Adapters::BaseAdapter
        # @param atomic_file_writer [Object, nil] Optional atomic writer implementation
        # @param logger [Object, nil] Optional logger
        def initialize(atomic_file_writer: nil, logger: nil)
          super(logger: logger)
          @writer = atomic_file_writer
        end

        # Write payload to path atomically when possible.
        #
        # Ensures the target directory exists before delegating to the underlying writer.
        def write(path, payload)
          dir = File.dirname(path)
          FileUtils.mkdir_p(dir)

          return default_write(path, payload) unless @writer

          @writer.write(path, payload)
        end

        private

        def default_write(path, payload)
          tmp = "#{path}.tmp"
          File.write(tmp, payload)
          FileUtils.mv(tmp, path)
        ensure
          FileUtils.rm_f(tmp) if tmp && File.exist?(tmp)
        end
      end
    end
  end
end
