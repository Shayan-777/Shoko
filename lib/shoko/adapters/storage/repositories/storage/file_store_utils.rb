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

            # Load an object-shaped JSON store, degrading to empty when the data
            # cannot be used so a single bad sidecar (annotations/bookmarks/
            # progress) never blocks opening the book. The two failure modes are
            # handled differently:
            #
            # - A CONTENT error — unparseable JSON, or a valid-but-wrong-shape
            #   payload (a bare array/scalar from a partial or externally-synced
            #   write) — means the file on disk is corrupt. The callers do a
            #   read-modify-write, so returning empty here would let the very
            #   next save OVERWRITE the corrupt file and destroy recoverable,
            #   user-authored data (highlights, notes, reading positions). The
            #   corrupt file is therefore QUARANTINED first (renamed aside,
            #   mirroring RssReaderRepository#quarantine_corrupt_file) and only
            #   then does the read degrade to empty: the quarantine copy stays on
            #   disk for recovery and the next save writes a clean file.
            #
            # - An ACCESS error (missing file, permissions, transient IO) is not
            #   corruption — the bytes may be intact and merely unreadable right
            #   now — so it degrades to empty WITHOUT quarantining, and a
            #   transient read failure never moves a healthy file aside.
            def load_json_or_empty(file_path, logger: nil)
              return {} unless File.exist?(file_path)

              parsed = JSON.parse(File.read(file_path))
              return parsed if parsed.is_a?(Hash)

              quarantine_corrupt_file(file_path, logger, reason: 'non-object payload')
              {}
            rescue JSON::ParserError => e
              quarantine_corrupt_file(file_path, logger, reason: e.message)
              {}
            rescue SystemCallError, IOError
              {}
            end

            # Move a corrupt store file aside so the next save cannot clobber it.
            # Best-effort: a failed quarantine leaves the file in place (no worse
            # than the previous silent-empty behavior) and never raises into the
            # load path. Returns the quarantine path on success, nil otherwise.
            def quarantine_corrupt_file(file_path, logger, reason:)
              quarantine_path = unique_quarantine_path(file_path)
              File.rename(file_path, quarantine_path)
              logger&.warn('file_store.corrupt_file_quarantined',
                           from: file_path, to: quarantine_path, reason: reason)
              quarantine_path
            # resilient-boundary
            rescue StandardError => e
              record_quarantine_error(logger, e, file_path)
            end

            def record_quarantine_error(logger, error, file_path)
              logger&.warn('file_store.quarantine_failed',
                           path: file_path, error_class: error.class.name, error: error.message)
              nil
            end

            # `<path>.corrupt-<UTC timestamp>`, disambiguated with a counter on
            # the (near-impossible) chance two quarantines land in the same
            # second, so an earlier quarantine is never overwritten.
            def unique_quarantine_path(file_path)
              base = "#{file_path}.corrupt-#{Time.now.utc.strftime('%Y%m%d%H%M%S')}"
              return base unless File.exist?(base)

              index = 1
              index += 1 while File.exist?("#{base}-#{index}")
              "#{base}-#{index}"
            end
          end
        end
      end
    end
  end
end
