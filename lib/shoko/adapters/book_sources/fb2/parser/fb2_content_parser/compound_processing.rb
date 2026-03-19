# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Fb2
        class Fb2ContentParser
          # Handles nested FB2 poem, quote, epigraph, and table elements.
          module CompoundProcessing
            private

            def process_poem(element)
              each_element_child(element) { |child| process_poem_child(child) }
            end

            def process_poem_child(child)
              case element_name(child)
              when 'title'
                process_title(child, depth: 2)
              when 'stanza'
                process_stanza(child)
              when 'text-author'
                append_attribution_block(child)
              when 'epigraph'
                process_epigraph(child)
              end
            end

            def process_stanza(stanza)
              each_element_child(stanza) do |child|
                next unless element_name(child) == 'v'

                append_quote_block(Fb2InlineParser.build_segments(child), metadata: { style: :verse })
              end
            end

            def process_cite(element)
              process_quote_container(element, epigraph: false)
            end

            def process_epigraph(element)
              process_quote_container(element, epigraph: true)
            end

            def process_quote_container(element, epigraph:)
              each_element_child(element) { |child| process_quote_child(child, epigraph: epigraph) }
            end

            def process_quote_child(child, epigraph:)
              name = element_name(child)
              return append_quote_paragraph(child, epigraph: epigraph) if name == 'p'

              process_nested_quote_child(child, name, epigraph: epigraph)
            end

            def append_quote_paragraph(element, epigraph:)
              segments = Fb2InlineParser.build_segments(element)
              return if segments.empty?

              segments = italicize_segments(segments) if epigraph
              metadata = epigraph ? { style: :epigraph, align: :right } : {}
              append_quote_block(segments, metadata: metadata)
            end

            def process_nested_quote_child(child, name, epigraph:)
              return process_epigraph_quote_child(child, name) if epigraph

              process_standard_quote_child(child, name)
            end

            def process_standard_quote_child(child, name)
              case name
              when 'poem'
                process_poem(child)
              when 'text-author'
                append_attribution_block(child)
              when 'subtitle'
                process_subtitle(child)
              when 'empty-line'
                process_empty_line
              when 'table'
                process_table(child)
              end
            end

            def process_epigraph_quote_child(child, name)
              case name
              when 'poem'
                process_poem(child)
              when 'cite'
                process_cite(child)
              when 'text-author'
                append_attribution_block(child)
              when 'empty-line'
                process_empty_line
              end
            end

            def process_table(element)
              rows = table_rows(element)
              return if rows.empty?

              table_text = rows.map { |row| row.map { |cell| cell[:text] }.join(' | ') }.join("\n")
              segments = [Core::Models::TextSegment.new(text: table_text, styles: {})]
              append_block(:table, segments, metadata: { table: { rows: rows } })
            end

            def table_rows(element)
              rows = []
              each_element_child(element) do |child|
                next unless element_name(child) == 'tr'

                cells = table_cells(child)
                rows << cells unless cells.empty?
              end
              rows
            end

            def table_cells(row_element)
              each_element_child(row_element).filter_map do |cell|
                name = element_name(cell)
                next unless %w[th td].include?(name)

                { text: Fb2InlineParser.plain_text(cell), header: name == 'th' }
              end
            end
          end
        end
      end
    end
  end
end
