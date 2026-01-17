# frozen_string_literal: true

require 'fileutils'
require_relative '../../core/services/base_service'

module Shoko
  module Adapters::Storage
    # Provides atomic file writing for domain repositories without coupling them
    # to infrastructure implementations.
    class FileWriterService < BaseService
      def initialize(dependencies)
        super
        @writer = resolve_optional(:atomic_file_writer)
      end

      # Write payload to path atomically when possible.
      #
      # Ensures the target directory exists before delegating to the underlying writer.
      def write(path, payload)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir)

        if @writer.respond_to?(:write)
          @writer.write(path, payload)
        else
          default_write(path, payload)
        end
      end

      private

      def resolve_optional(name)
        resolve(name)
      rescue StandardError
        nil
      end

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
