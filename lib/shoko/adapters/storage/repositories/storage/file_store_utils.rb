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

            # A corrupt, truncated, or externally-synced (Dropbox/rsync conflict,
            # a second Shoko instance, a hand-edit) store file is semantically
            # equivalent to "no data yet": the layout-independent reads degrade to
            # empty so a single bad sidecar (annotations/bookmarks/progress) never
            # blocks opening the book. This mirrors recent.json and rss_reader.json,
            # which already rescue at their own load — and the file's own
            # ProgressRepository#parse_timestamp, which degrades unparseable input
            # to "unknown". JSON::ParserError and Errno::* are not Shoko::Error, so
            # rescuing the real classes here is the §VIII "translate at the source"
            # option rather than leaking a raw StandardError through the repository's
            # narrow `rescue Shoko::Error`. A valid-but-wrong-shape payload (a bare
            # array/scalar from a partial write) is treated as empty for the same
            # reason.
            def load_json_or_empty(file_path)
              return {} unless File.exist?(file_path)

              parsed = JSON.parse(File.read(file_path))
              parsed.is_a?(Hash) ? parsed : {}
            rescue JSON::ParserError, SystemCallError, IOError
              {}
            end
          end
        end
      end
    end
  end
end
