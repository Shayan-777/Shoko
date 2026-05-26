# frozen_string_literal: true

module Shoko
  module Application
    module Ports
      module Outbound
        # Boundary for reading and writing imported book cache payloads.
        module BookCacheStore
          CacheEntry = Data.define(:book, :cache_path, :source_path, :source_sha, :loaded_from_cache, :payload)

          def fetch(path, strict: true)
            raise NotImplementedError, "#{self.class} must implement #fetch"
          end

          def write(path, book_data)
            raise NotImplementedError, "#{self.class} must implement #write"
          end
        end
      end
    end
  end
end
