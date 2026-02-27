# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      # Source resolution helpers for `EpubCache` (EPUB source vs `.cache` pointer file).
      class EpubCache
        private

        def setup_source_reference
          if self.class.cache_file?(@raw_path)
            setup_source_reference_from_pointer
          else
            setup_source_reference_from_epub
          end
        end

        def setup_source_reference_from_pointer
          @cache_path = @raw_path
          @pointer_manager = CachePointerManager.new(@cache_path)
          pointer = @pointer_manager.read
          raise Shoko::CacheLoadError.new(@raw_path, 'invalid pointer file') unless pointer

          @source_type = :cache_pointer
          @pointer_metadata = pointer
          @source_sha = pointer['sha256']
          @source_path = pointer['source_path']
        end

        def setup_source_reference_from_epub
          raise Shoko::FileNotFoundError, @raw_path unless File.file?(@raw_path)

          @source_type = :epub
          @source_path = @raw_path
          @source_sha = Digest::SHA256.file(@source_path).hexdigest
          @cache_path = cache_path_for_source_sha
          @pointer_manager = CachePointerManager.new(@cache_path)
          @pointer_metadata = @pointer_manager.read
        end

        def cache_path_for_source_sha
          cache_path = self.class.cache_path_for_sha(@source_sha, cache_root: @cache_root)
          raise Shoko::CacheLoadError.new(@raw_path, 'invalid sha256 digest') unless cache_path

          cache_path
        end

        def ensure_sha!
          return if @source_sha

          if @source_type == :epub
            @source_sha = Digest::SHA256.file(@source_path).hexdigest
          elsif @pointer_metadata
            @source_sha = @pointer_metadata['sha256']
          end
        end
      end
    end
  end
end
