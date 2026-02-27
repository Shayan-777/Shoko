# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      class BookCachePipeline
        # Filters manifest rows by source fingerprint, keeping untagged rows.
        class FingerprintFilter
          def initialize(source_path)
            @source_path = source_path
            @fingerprint = nil
            @fingerprint_blank = false
          end

          def call(rows)
            matches = rows.select { |row| include_row?(row) }
            [matches, applied?, blank?]
          end

          private

          def include_row?(row)
            value = row.fingerprint_value
            return true unless value

            ensure_fingerprint
            return false if @fingerprint_blank

            value == @fingerprint
          end

          def ensure_fingerprint
            return if @fingerprint

            @fingerprint = Shoko::Shared::SourceFingerprint.compute(@source_path).to_s
            @fingerprint_blank = @fingerprint.empty?
          end

          def applied?
            !!@fingerprint
          end

          def blank?
            @fingerprint_blank
          end
        end

        private_constant :FingerprintFilter
      end
    end
  end
end
