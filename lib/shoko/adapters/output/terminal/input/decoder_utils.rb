# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Terminal
        class TerminalInput
          # Utility helpers for timeouts and CSI formatting.
          module DecoderUtils
            module_function

            def normalize_timeout(value, default)
              seconds = value.to_f
              seconds.positive? ? seconds : default
            end

            def monotonic_now
              Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end

            def format_csi_output(raw, prefix_bytes, output_prefix)
              return raw.force_encoding(Encoding::UTF_8) unless output_prefix

              remainder = raw.byteslice(prefix_bytes..) || ''.b
              (output_prefix + remainder.force_encoding(Encoding::UTF_8)).freeze
            end
          end
        end
      end
    end
  end
end
