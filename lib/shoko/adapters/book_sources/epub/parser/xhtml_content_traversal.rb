# frozen_string_literal: true

require 'rexml/document'

require_relative 'list_marker'
require_relative 'markup_visibility'

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Traverses elements and emits block structures.
        class XHTMLContentTraversal
          # Traversal state: list nesting, blockquote membership, inherited
          # alignment, semantic role scope (subtitle/verse/caption), and the
          # boxed-container group blocks belong to.
          Context = Struct.new(:list_stack, :in_blockquote, :align, :role, :box_group)
          private_constant :Context

          VERSE_TYPE_PATTERN = /(?:\bverse\b|\bpoem\b|z3998:verse|z3998:poem)/i

          def initialize(block_builder:, tag_sets:, style_resolver: nil)
            @block_builder = block_builder
            @tag_sets = tag_sets
            @style_resolver = style_resolver
            @blocks = []
            @pending_anchors = []
            @pending_spacing_before = nil
            @box_counter = 0
          end

          def build(root)
            context = Context.new(list_stack: [], in_blockquote: false, align: nil, role: nil, box_group: nil)
            traverse_children(root, context)
            @block_builder.compact_blocks(@blocks)
          end

          private

          attr_reader :block_builder, :tag_sets

          def traverse_children(node, context)
            node.children.each { |child| handle_node(child, context) }
          end

          def handle_node(child, context)
            if child.is_a?(REXML::Element)
              handle_element(child, context)
            elsif child.is_a?(REXML::Text)
              append_text_block(child, context)
            end
          end

          def handle_element(element, context)
            name = element.name.downcase
            return if skip_element?(name)
            return if hidden_element?(element)

            context = semantic_context(name, element, context)
            return if appended_block_result?(block_builder.block_for(name, element, context))
            return if handled_quote_element?(name, element, context)
            return if handled_list_element?(name, element, context)
            return if handled_definition_element?(name, element, context)
            return if handled_container_element?(name, element, context)

            with_container_spacing(element) { traverse_children(element, context) }
          end

          # Semantic scopes an element opens for its descendants: hgroup title
          # paragraphs become subtitles, epub:type verse/poem containers mark
          # verse blocks, and figcaption paragraphs become captions.
          def semantic_context(name, element, context)
            role = semantic_role(name, element)
            role ? context_with(context, role: role) : context
          end

          def semantic_role(name, element)
            return :subtitle if name == 'hgroup'
            return :caption if name == 'figcaption'

            epub_type = element.attributes['epub:type'].to_s
            return nil if epub_type.empty?
            return :verse if VERSE_TYPE_PATTERN.match?(epub_type)
            return :epigraph if epub_type.include?('epigraph')

            nil
          end

          def context_with(context, **overrides)
            Context.new(
              list_stack: overrides.fetch(:list_stack, context.list_stack),
              in_blockquote: overrides.fetch(:in_blockquote, context.in_blockquote),
              align: overrides.fetch(:align, context.align),
              role: overrides.fetch(:role, context.role),
              box_group: overrides.fetch(:box_group, context.box_group)
            )
          end

          def appended_block_result?(result)
            return false unless result

            if result.is_a?(Array)
              result.each { |block| append_block(block) }
            else
              append_block(result)
            end
            true
          end

          def handled_quote_element?(name, element, context)
            return false unless name == tag_sets[:blockquote]

            if block_builder.contains_block_children?(element, tag_sets[:block_level_elements])
              with_container_spacing(element) { traverse_children(element, quoted_context(context)) }
            else
              append_block(block_builder.quote_block(element, context))
            end
            true
          end

          def quoted_context(context)
            context_with(context, in_blockquote: true)
          end

          def handled_list_element?(name, element, context)
            if tag_sets[:list_types].include?(name)
              traverse_list(element, context, ordered: name == 'ol')
              return true
            end

            return false unless name == tag_sets[:list_item]

            item, block_children = block_builder.list_item_with_children(element, context)
            append_block(item)
            block_children.each { |child| handle_element(child, context) }
            true
          end

          def handled_definition_element?(name, element, context)
            return false unless tag_sets[:definition_types].include?(name)

            case name
            when 'dl' then traverse_children(element, context)
            when 'dt' then append_block(block_builder.term_block(element, context))
            when 'dd' then handle_definition_description(element, context)
            end
            true
          end

          def handle_definition_description(element, context)
            if block_builder.contains_block_children?(element, tag_sets[:block_level_elements])
              traverse_children(element, context)
            else
              append_block(block_builder.definition_block(element, context))
            end
          end

          def handled_container_element?(name, element, context)
            block_types = tag_sets[:block_types]
            block_level = tag_sets[:block_level_elements]
            return false unless block_types.include?(name) || block_builder.block_via_style?(element)

            child_context = container_child_context(name, element, context)
            if block_builder.contains_block_children?(element, block_level)
              with_container_spacing(element) { traverse_children(element, child_context) }
            else
              append_block(block_builder.paragraph(element, child_context))
            end
            true
          end

          # A container's own margins land on its first and last emitted
          # blocks, collapsing with the blocks' own margins the way CSS
          # collapses adjacent vertical margins (the larger one wins).
          def with_container_spacing(element)
            spacing = container_spacing(element)
            before = spacing[:spacing_before]
            @pending_spacing_before = [@pending_spacing_before.to_i, before].max if before
            first_index = @blocks.length
            yield
            apply_container_spacing_after(first_index, spacing[:spacing_after])
          end

          def container_spacing(element)
            return {} unless @style_resolver

            metadata = @style_resolver.block_metadata(element)
            { spacing_before: metadata[:spacing_before], spacing_after: metadata[:spacing_after] }
          end

          def apply_container_spacing_after(first_index, spacing_after)
            return unless spacing_after

            last = @blocks.last
            return unless last && @blocks.length > first_index

            current = last.metadata[:spacing_after].to_i
            @blocks[-1] = last.with(metadata: last.metadata.merge(spacing_after: [current, spacing_after].max))
          end

          def container_child_context(name, element, context)
            child_context = name == 'center' ? context_with(context, align: :center) : context
            return child_context unless boxed_container?(element)

            @box_counter += 1
            context_with(child_context, box_group: @box_counter)
          end

          def boxed_container?(element)
            @style_resolver&.block_metadata(element)&.dig(:boxed) ? true : false
          end

          def append_text_block(text_node, context)
            segments = block_builder.segments_from_text(text_node.value)
            append_block(block_builder.paragraph_from_segments(segments, context)) if segments
          end

          def traverse_list(element, context, ordered:)
            list_context = ListMarker.context_for(element,
                                                  ordered: ordered,
                                                  depth: context.list_stack.length,
                                                  css_style: @style_resolver&.list_style(element))
            new_context = context_with(context, list_stack: context.list_stack + [list_context])
            element.each_element { |child| handle_element(child, new_context) }
          end

          def append_block(block)
            return unless block

            block = attach_pending_anchors(block)
            block = attach_pending_spacing(block)
            @blocks << block
          end

          def attach_pending_spacing(block)
            return block unless @pending_spacing_before

            current = block.metadata[:spacing_before].to_i
            block = block.with(metadata: block.metadata.merge(
              spacing_before: [current, @pending_spacing_before].max
            ))
            @pending_spacing_before = nil
            block
          end

          def skip_element?(name)
            %w[script style].include?(name)
          end

          # Elements hidden via CSS or their own markup are pruned, but any
          # anchor ids inside them must survive — TOC entries and footnote
          # links target them. They are carried onto the next visible block.
          def hidden_element?(element)
            hidden = MarkupVisibility.markup_hidden?(element) || @style_resolver&.display_none?(element)
            return false unless hidden

            @pending_anchors.concat(block_builder.anchor_ids_for(element) || [])
            true
          end

          def attach_pending_anchors(block)
            return block if @pending_anchors.empty?

            anchors = Array(block.metadata[:anchors]) + @pending_anchors
            block = block.with(metadata: block.metadata.merge(anchors: anchors.uniq))
            @pending_anchors = []
            block
          end
        end
      end
    end
  end
end
