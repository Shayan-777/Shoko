# frozen_string_literal: true

require 'shoko/shared/errors'

module Shoko
  module Adapters
    module BookSources
      # Resolves and validates a local book path before an importer reads it.
      #
      # Every file-backed importer needs the same guarantee — an absolute path
      # that exists — and the same typed failure when it does not.
      module SourcePath
        module_function

        # @raise [Shoko::FileNotFoundError] when no regular file exists there
        # @return [String] absolute path
        def validated(path)
          expanded = File.expand_path(path)
          raise Shoko::FileNotFoundError, path unless File.file?(expanded)

          expanded
        end
      end
    end
  end
end
