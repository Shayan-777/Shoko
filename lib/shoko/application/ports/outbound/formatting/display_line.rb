# frozen_string_literal: true

require_relative '../../../../shared/hash_normalizer'

module Shoko
  module Application
    module Ports
      module Outbound
        module Formatting
          # Display-ready line produced by the formatting pipeline and
          # consumed across the rendering layer.
          #
          # Lives with the `ChapterFormatter` port because it is the data
          # the port returns. Adapters that implement or consume the port
          # may reference it via the `Application::Ports::*` carve-out;
          # the application layer (pagination services, navigation
          # snappers) may reference it directly. Core code must NOT
          # branch on this type — it duck-distinguishes by `String` vs.
          # other line-like objects via `case ... when String`.
          DisplayLine = Struct.new(:text, :segments, :metadata) do
            def initialize(text:, segments:, metadata: nil)
              super(
                text: text.to_s,
                segments: segments || [],
                metadata: Shoko::Shared::HashNormalizer.deep_symbolize(metadata) || {}
              )
            end

            def length
              text.length
            end

            def empty?
              text.strip.empty?
            end
          end
        end
      end
    end
  end
end
