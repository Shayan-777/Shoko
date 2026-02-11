# frozen_string_literal: true

module Shoko
  module Core
    module Ports
      # Focused reader for menu text-entry/query fields.
      module MenuQueryReader
        def search_query
          raise NotImplementedError, "#{self.class} must implement #search_query"
        end

        def search_cursor
          raise NotImplementedError, "#{self.class} must implement #search_cursor"
        end

        def search_active?
          raise NotImplementedError, "#{self.class} must implement #search_active?"
        end

        def download_query
          raise NotImplementedError, "#{self.class} must implement #download_query"
        end

        def download_cursor
          raise NotImplementedError, "#{self.class} must implement #download_cursor"
        end

        def dictionary_query
          raise NotImplementedError, "#{self.class} must implement #dictionary_query"
        end

        def dictionary_cursor
          raise NotImplementedError, "#{self.class} must implement #dictionary_cursor"
        end
      end
    end
  end
end
