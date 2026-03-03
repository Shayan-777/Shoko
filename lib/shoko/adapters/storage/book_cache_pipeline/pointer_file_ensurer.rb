# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      class BookCachePipeline
        # Ensures pointer metadata exists on disk for a cached source.
        class PointerFileEnsurer
          def initialize(pointer_path:, sha:, source_path:, manager_class:, logger: nil)
            @pointer_path = pointer_path
            @sha = sha
            @source_path = source_path
            @manager_class = manager_class
            @logger = logger
          end

          def call
            manager = @manager_class.new(@pointer_path, logger: @logger)
            existing = manager.read
            return if current?(existing)

            manager.write(metadata)
          rescue Shoko::Error
            raise
          end

          private

          def current?(existing)
            existing && existing['sha256'] == @sha && existing['source_path'].to_s == @source_path
          end

          def metadata
            {
              'format' => @manager_class::POINTER_FORMAT,
              'version' => @manager_class::POINTER_VERSION,
              'sha256' => @sha,
              'source_path' => @source_path,
              'generated_at' => Time.now.utc.iso8601,
              'engine' => JsonCacheStore::ENGINE,
            }
          end
        end

        private_constant :PointerFileEnsurer
      end
    end
  end
end
