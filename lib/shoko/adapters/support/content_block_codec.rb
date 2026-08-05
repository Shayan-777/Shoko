# frozen_string_literal: true

require 'shoko/core/models/block_type'
require 'shoko/core/models/content_block'
require 'shoko/core/models/text_segment'
require 'shoko/shared/hash_normalizer'

module Shoko
  module Adapters
    module Support
      # Translates formatted-content values to and from JSON-safe payloads.
      module ContentBlockCodec
        module_function

        def dump(blocks)
          Array(blocks).map { |block| dump_block(block) }
        end

        def load(payloads)
          Array(payloads).filter_map { |payload| load_block(payload) }
        end

        def dump_block(block)
          {
            type: Core::Models::BlockType.canonical(block.type).to_s,
            level: block.level.to_i,
            metadata: stringify(block.metadata),
            segments: Array(block.segments).map { |segment| dump_segment(segment) },
          }
        end

        def load_block(payload)
          return payload if payload.is_a?(Core::Models::ContentBlock)

          fields = Shared::HashNormalizer.symbolize_keys(payload)
          return nil unless fields

          Core::Models::ContentBlock.new(
            type: Core::Models::BlockType.canonical(fields[:type]),
            segments: Array(fields[:segments]).filter_map { |segment| load_segment(segment) },
            level: fields[:level].to_i,
            metadata: fields[:metadata]
          )
        end

        def dump_segment(segment)
          { text: segment.text.to_s, styles: stringify(segment.styles) }
        end

        def load_segment(payload)
          return payload if payload.is_a?(Core::Models::TextSegment)

          fields = Shared::HashNormalizer.symbolize_keys(payload)
          return nil unless fields

          Core::Models::TextSegment.new(text: fields[:text], styles: fields[:styles])
        end

        def stringify(value)
          case value
          when Hash
            value.to_h { |key, child| [key.to_s, stringify(child)] }
          when Array
            value.map { |child| stringify(child) }
          when Symbol
            value.to_s
          else
            value
          end
        end
      end
    end
  end
end
