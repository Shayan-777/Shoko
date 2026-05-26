# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Port interface for deleting on-disk user/cache data safely.
        module DataCleanup
          # @param cache_root [String, nil]
          # @return [void]
          def remove_cache_root(cache_root)
            raise NotImplementedError, "#{self.class} must implement #remove_cache_root"
          end

          # @param config_root [String, nil]
          # @return [void]
          def remove_downloads_root(config_root)
            raise NotImplementedError, "#{self.class} must implement #remove_downloads_root"
          end

          # @param config_root [String, nil]
          # @param annotations [Boolean]
          # @param bookmarks [Boolean]
          # @param progress [Boolean]
          # @param config_file [Boolean]
          # @return [void]
          def remove_user_data_files(config_root:, annotations:, bookmarks:, progress:, config_file:)
            raise NotImplementedError, "#{self.class} must implement #remove_user_data_files"
          end
        end
      end
    end
  end
end
