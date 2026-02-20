# frozen_string_literal: true

module Shoko
  module Adapters::Output::Ui::Components
    module Ui
      # Shared list input behavior for annotation editors.
      module AnnotationListInput
        BULLET = '●'
        BULLET_PREFIX = "#{BULLET} ".freeze

        module_function

        def insert_character(text, cursor, char)
          updated = text.to_s.dup
          updated.insert(cursor, char)
          new_cursor = cursor + char.length

          return [updated, new_cursor] unless char == ' '

          line_start = line_start_index(updated, new_cursor)
          prefix = updated[line_start...new_cursor].to_s
          match = prefix.match(/\A(\s*)-\s\z/)
          return [updated, new_cursor] unless match

          indent = match[1]
          replacement = "#{indent}#{BULLET_PREFIX}"
          updated[line_start...new_cursor] = replacement
          [updated, line_start + replacement.length]
        end

        def insert_newline(text, cursor)
          updated = text.to_s.dup
          line_start, _, line = line_bounds(updated, cursor)

          bullet_prefix = bullet_prefix_for(line)
          if bullet_prefix
            content = line[bullet_prefix.length..].to_s
            return exit_list(updated, cursor, line_start, bullet_prefix.length) if content.strip.empty?

            insert = "\n#{bullet_prefix}"
            updated.insert(cursor, insert)
            return [updated, cursor + insert.length]
          end

          number_prefix = numbered_prefix_for(line)
          if number_prefix
            indent, number, prefix = number_prefix.values_at(:indent, :number, :prefix)
            content = line[prefix.length..].to_s
            return exit_list(updated, cursor, line_start, prefix.length) if content.strip.empty?

            insert = "\n#{indent}#{number + 1}. "
            updated.insert(cursor, insert)
            return [updated, cursor + insert.length]
          end

          updated.insert(cursor, "\n")
          [updated, cursor + 1]
        end

        def bullet_prefix_for(line)
          match = line.match(/\A(\s*)#{Regexp.escape(BULLET)}\s/o)
          return nil unless match

          "#{match[1]}#{BULLET_PREFIX}"
        end

        def numbered_prefix_for(line)
          match = line.match(/\A(\s*)(\d+)\.\s/)
          return nil unless match

          indent = match[1]
          number = match[2].to_i
          { indent: indent, number: number, prefix: "#{indent}#{number}. " }
        end

        def line_bounds(text, cursor)
          line_start = line_start_index(text, cursor)
          line_end = text.index("\n", cursor) || text.length
          line = text[line_start...line_end].to_s
          [line_start, line_end, line]
        end

        def line_start_index(text, cursor)
          idx = text.rindex("\n", cursor - 1)
          idx ? (idx + 1) : 0
        end

        def exit_list(text, cursor, line_start, prefix_length)
          text.slice!(line_start, prefix_length)
          new_cursor = cursor
          new_cursor -= prefix_length if cursor >= line_start + prefix_length
          text.insert(new_cursor, "\n")
          [text, new_cursor + 1]
        end
      end
    end
  end
end
