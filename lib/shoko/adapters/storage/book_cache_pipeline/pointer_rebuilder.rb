# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      class BookCachePipeline
        # Rebuilds pointer caches by loading the original source file.
        class PointerRebuilder
          def initialize(cache:, formatting_service:, load_callback:, logger: nil)
            @cache = cache
            @formatting_service = formatting_service
            @load_callback = load_callback
            @cache_class = cache.class
            @logger = logger
          end

          def call
            return nil unless pointer_source_valid?

            rebuild
          rescue Shoko::Error => e
            log_failure(e)
            nil
          end

          private

          def pointer_source_valid?
            path = source_path
            return false if path.empty?
            return false if @cache_class.cache_file?(path)

            File.file?(path)
          rescue Shoko::Error
            raise
          end

          def rebuild
            rebuilt = @load_callback.call(source_path, formatting_service: @formatting_service)
            PointerCacheCleaner.new(cache_path, rebuilt&.cache_path).call
            rebuilt
          end

          def cache_path
            @cache.cache_path
          end

          def source_path
            @source_path ||= @cache.source_path.to_s
          end

          def log_failure(error)
            @logger&.error(
              'Pointer cache rebuild failed',
              cache: cache_path,
              source: source_path,
              error: error.message
            )
          end
        end

        private_constant :PointerRebuilder
      end
    end
  end
end
