# frozen_string_literal: true

require 'time'
require_relative 'base_file_store'

module Shoko
  module Adapters
    module Storage
      module Repositories
        module Storage
          # File-backed progress storage under Domain.
          # Persists progress to ${XDG_CONFIG_HOME:-~/.config}/shoko/progress.json
          class ProgressFileStore < BaseFileStore
            FILE_NAME = 'progress.json'
            SCHEMA_VERSION = 1

            def save(path, chapter_index, line_offset, anchor = nil)
              all = load_all
              payload = { 'chapter' => chapter_index, 'line_offset' => line_offset, 'timestamp' => Time.now.iso8601 }
              payload['anchor'] = anchor if anchor
              all[path.to_s] = payload
              save_all(all)
              payload
            end

            def load(path)
              all = load_all
              all[path.to_s]
            end

            # Make load_all public for this store (needed by repository)
            public :load_all
          end
        end
      end
    end
  end
end
