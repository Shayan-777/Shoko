# frozen_string_literal: true

module Shoko
  module Core
    module Services
      # Canonical form of the size/mtime pair used to decide whether a cached
      # display-metadata entry still matches the file on disk.
      #
      # The catalog service writes these values and the cache repository compares
      # them; if the two normalizations ever drifted, every comparison would fail
      # (or wrongly succeed) and the cache would silently stop working. One
      # definition keeps writer and reader in agreement by construction.
      module DisplayMetadataFingerprint
        module_function

        # @return [Integer, nil] nil when absent or not an integer
        def size(value)
          return nil if value.nil?

          string = value.to_s.strip
          return nil if string.empty?

          Integer(string, exception: false)
        end

        # @return [String, nil] nil when absent or blank
        def modified(value)
          return nil if value.nil?

          string = value.to_s.strip
          string.empty? ? nil : string
        end
      end
    end
  end
end
