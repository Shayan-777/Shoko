# frozen_string_literal: true

require_relative '../../core/ports/recent_files_repository'
require_relative 'recent_files'

module Shoko
  module Adapters
    module Storage
      # Adapter wrapper for recent files persistence.
      class RecentFilesRepository
        include Core::Ports::RecentFilesRepository

        def add(path)
          RecentFiles.add(path)
        end

        def load
          RecentFiles.load
        end

        def clear
          RecentFiles.clear
        end
      end
    end
  end
end
