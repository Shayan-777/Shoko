# frozen_string_literal: true

require 'English'
require 'fileutils'
require 'tempfile'
require_relative '../../shared/errors'

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
          tempfile = nil
          begin
            dir = File.dirname(path)
            FileUtils.mkdir_p(dir)
            tempfile = prepare_tempfile(path, dir, binary)
            yield(tempfile)
            commit_tempfile(tempfile, path)
          rescue StandardError => e
            raise_storage_error('atomic_write', path, e)
          ensure
            cleanup_error = cleanup_tempfile(tempfile, path)
            raise cleanup_error if cleanup_error && $ERROR_INFO.nil?
          end
        end

        def self.prepare_tempfile(path, dir, binary)
          tempfile = Tempfile.new(['shoko', File.basename(path)], dir)
          tempfile.binmode if binary
          tempfile
        end

        def self.commit_tempfile(tempfile, path)
          tempfile.flush
          tempfile.fsync
          temp_path = tempfile.path
          tempfile.close
          File.rename(temp_path, path)
          fsync_directory(File.dirname(path))
        end

        # The tempfile's bytes are fsync'd above, but the atomic rename is a
        # directory-metadata change: without fsync'ing the containing
        # directory a crash or power loss can lose the rename even though the
        # data was flushed, leaving the target missing or zero-length (which
        # the file-backed stores then read as a corrupt sidecar). Best-effort —
        # some platforms (e.g. Windows) cannot fsync a directory handle, and
        # that must never fail an otherwise-successful write.
        def self.fsync_directory(dir)
          File.open(dir, &:fsync)
        rescue SystemCallError, IOError, NotImplementedError
          # best-effort: platforms that cannot fsync a directory handle skip it
        end

        def self.cleanup_tempfile(tempfile, path)
          return nil unless tempfile

          begin
            tempfile.close unless tempfile.closed?
          rescue StandardError => e
            return storage_error('atomic_write_cleanup_close', path, e)
          end

          begin
            tempfile.unlink if tempfile.path && File.exist?(tempfile.path)
          rescue StandardError => e
            return storage_error('atomic_write_cleanup_unlink', path, e)
          end

          nil
        end

        def self.storage_error(operation, path, error)
          return error if error.is_a?(Shoko::Error)

          Shoko::StorageError.new(operation, path.to_s, error.message)
        end

        def self.raise_storage_error(operation, path, error)
          raise storage_error(operation, path, error)
        end

        private_class_method :prepare_tempfile,
                             :commit_tempfile,
                             :fsync_directory,
                             :cleanup_tempfile,
                             :storage_error,
                             :raise_storage_error
      end
    end
  end
end
