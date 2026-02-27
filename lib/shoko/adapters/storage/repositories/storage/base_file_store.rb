# frozen_string_literal: true

require 'json'
require_relative 'file_store_utils'
require_relative '../../config_paths'

module Shoko
  module Adapters
    module Storage
      module Repositories
        module Storage
          # Base class for file-backed JSON storage.
          # Provides common file I/O operations for all file stores.
          class BaseFileStore
            def initialize(file_writer:)
              @file_writer = file_writer
            end

            protected

            attr_reader :file_writer

            def load_all
              FileStoreUtils.load_json_or_empty(file_path)
            end

            def save_all(data)
              payload = JSON.pretty_generate(data)
              file_writer.write(file_path, payload)
            end

            def file_path
              Adapters::Storage::ConfigPaths.config_path(self.class::FILE_NAME)
            end
          end
        end
      end
    end
  end
end
