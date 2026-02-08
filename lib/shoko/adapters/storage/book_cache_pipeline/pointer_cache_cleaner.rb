# frozen_string_literal: true

module Shoko
  module Adapters::Storage
    class BookCachePipeline
      # Removes stale pointer cache files after a rebuild.
      class PointerCacheCleaner
        def initialize(cache_path, rebuilt_path)
          @cache_path = cache_path
          @rebuilt_path = rebuilt_path
        end

        def call
          return unless @rebuilt_path
          return if same_path?

          FileUtils.rm_f(@cache_path)
        rescue StandardError
          nil
        end

        private

        def same_path?
          File.expand_path(@cache_path) == File.expand_path(@rebuilt_path)
        end
      end

      private_constant :PointerCacheCleaner
    end
  end
end
