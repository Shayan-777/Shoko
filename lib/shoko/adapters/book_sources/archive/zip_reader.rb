# frozen_string_literal: true

require_relative 'zip'

module Shoko
  module Adapters
    module BookSources
      module Archive
        # Adapter-owned archive facade used by book-source importers/loaders.
        module ZipReader
          module_function

          def open(path, runtime_config: nil, &)
            Zip::File.open(path, **zip_limit_kwargs(runtime_config), &)
          end

          def zip_limit_kwargs(runtime_config)
            return {} unless runtime_config

            {
              max_entry_uncompressed_bytes: runtime_config.zip_max_entry_uncompressed_bytes,
              max_entry_compressed_bytes: runtime_config.zip_max_entry_compressed_bytes,
              max_total_uncompressed_bytes: runtime_config.zip_max_total_uncompressed_bytes,
            }
          end
        end
      end
    end
  end
end
