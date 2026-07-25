# frozen_string_literal: true

module Shoko
  module Shared
    # Interpretation of a stored dictionary language preference.
    #
    # "auto" means "detect from the book"; so do nil, blank, and any casing of
    # the word. The install wizard, the settings screen, and the settings
    # service each read the same stored value and must agree on what it means.
    module DictionaryLanguageSetting
      AUTO = 'auto'

      module_function

      # @return [Boolean] true when the setting means "detect automatically"
      def auto?(value)
        return true if value.nil?

        text = value.to_s.strip
        text.empty? || text.casecmp(AUTO).zero?
      end
    end
  end
end
