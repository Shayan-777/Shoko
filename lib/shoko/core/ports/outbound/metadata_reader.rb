# frozen_string_literal: true

module Shoko
  module Core
    module Ports::Outbound
      # Port interface for reading book metadata.
      # Adapters implementing this interface should handle extracting
      # metadata (title, author, etc.) from book files.
      module MetadataReader
        # Extract metadata from a book file
        #
        # @param path [String] Path to the book file
        # @return [Hash] Metadata hash with keys like :title, :creator, :language, etc.
        def extract_metadata(path)
          raise NotImplementedError, "#{self.class} must implement #extract_metadata"
        end
      end
    end
  end
end
