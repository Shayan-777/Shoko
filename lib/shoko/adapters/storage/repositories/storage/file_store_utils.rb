# frozen_string_literal: true

require 'json'

module Shoko
  module Adapters
    module Storage
      module Repositories
        module Storage
          # Small, shared helpers for file-backed JSON stores.
          module FileStoreUtils
            module_function

            def load_json_or_empty(file_path)
              return {} unless File.exist?(file_path)

              JSON.parse(File.read(file_path))
            rescue StandardError
              {}
            end
          end
        end
      end
    end
  end
end
