# frozen_string_literal: true

require 'shoko/shared/errors'

module Shoko
  module Adapters
    module Storage
      # Translates a raw filesystem failure into the storage taxonomy at the
      # adapter edge (constitution R4: adapters translate at their boundary).
      # An error that is already a Shoko error passes through untouched, so a
      # translated error is never wrapped twice.
      module StorageErrorTranslation
        module_function

        # @raise [Shoko::Error] always
        def raise_storage_error(operation, path, error)
          raise error if error.is_a?(Shoko::Error)

          raise Shoko::StorageError.new(operation, path.to_s, error.message)
        end
      end
    end
  end
end
