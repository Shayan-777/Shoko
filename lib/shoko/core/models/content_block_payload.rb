# frozen_string_literal: true

require_relative 'content_block'
require_relative 'text_segment'
require_relative 'block_type'
require_relative '../../shared/hash_normalizer'

module Shoko
  module Core
    module Models
      # Converts content blocks to and from plain nested Hashes.
      #
      # Blocks reach two destinations that only accept plain data — the JSON
      # article cache and the frozen state tree — so the wire shape is defined
      # once, here with the model, rather than at each boundary. The round trip
      # is lossless and total: a payload that has been through JSON (where every
      # Symbol became a String) rebuilds into the same block as the original.
      module ContentBlockPayload
        module_function

        # @param blocks [Array<ContentBlock>]
        # @return [Array<Hash>] plain, JSON-safe payloads
        def dump(blocks)
          Array(blocks).map { |block| dump_block(block) }
        end

        # @param payloads [Array<Hash>]
        # @return [Array<ContentBlock>]
        def load(payloads)
          Array(payloads).filter_map { |payload| load_block(payload) }
        end

        def dump_block(block)
          {
            type: BlockType.canonical(block.type).to_s,
            level: block.level.to_i,
            metadata: stringify(block.metadata),
            segments: Array(block.segments).map { |segment| dump_segment(segment) },
          }
        end

        def load_block(payload)
          fields = Shoko::Shared::HashNormalizer.symbolize_keys(payload)
          return nil unless fields

          ContentBlock.new(
            type: BlockType.canonical(fields[:type]),
            segments: Array(fields[:segments]).filter_map { |segment| load_segment(segment) },
            level: fields[:level].to_i,
            metadata: fields[:metadata]
          )
        end

        def dump_segment(segment)
          { text: segment.text.to_s, styles: stringify(segment.styles) }
        end

        def load_segment(payload)
          fields = Shoko::Shared::HashNormalizer.symbolize_keys(payload)
          return nil unless fields

          TextSegment.new(text: fields[:text], styles: fields[:styles])
        end

        # Style and metadata values are flags, markers, and hrefs. Symbols do
        # not survive JSON, so they are written as Strings and re-symbolized on
        # the way back by the value objects' own normalization.
        def stringify(values)
          (values || {}).each_with_object({}) do |(key, value), acc|
            acc[key.to_s] = value.is_a?(Symbol) ? value.to_s : value
          end
        end
      end
    end
  end
end
