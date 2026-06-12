# frozen_string_literal: true

module Shoko
  module Adapters
    module Output
      module Formatting
        class FormattingService
          # Builds plain text fallback lines from parsed content blocks.
          module PlainLinesBuilder
            require_relative '../../../../core/models/block_type'

            module_function

            def build(blocks)
              lines = []
              blocks.to_a.each { |block| append_lines_for_block(lines, block) }
              trim_trailing_blank_lines(lines)
            end

            def append_lines_for_block(lines, block)
              type = Shoko::Core::Models::BlockType.canonical(block.type) || block.type

              case type
              when :heading, :paragraph, :image
                append_text_with_blank_line(lines, block.text)
              when :list_item
                lines << list_item_plain_text(block)
              when :quote
                append_text_with_blank_line(lines, "> #{block.text}")
              when :code, :table
                append_preformatted_lines(lines, block.text)
              when :separator
                lines << ('╌' * 40)
              end
            end

            def list_item_plain_text(block)
              indent = '  ' * [block.level.to_i - 1, 0].max
              marker = (block.metadata && block.metadata[:marker]) || '•'
              "#{indent}#{marker} #{block.text}"
            end

            def append_text_with_blank_line(lines, text)
              lines << text
              lines << ''
            end

            def append_preformatted_lines(lines, text)
              text.to_s.split(/\r?\n/).each { |row| lines << row.rstrip }
              lines << ''
            end

            def trim_trailing_blank_lines(lines)
              lines.pop while lines.last&.strip&.empty?
              lines
            end
          end
        end
      end
    end
  end
end
