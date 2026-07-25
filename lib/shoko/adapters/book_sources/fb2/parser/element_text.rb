# frozen_string_literal: true

require 'rexml/document'

module Shoko
  module Adapters
    module BookSources
      module Fb2
        # Flattens an FB2 element's descendant text into a single string.
        #
        # Both the section flattener and the metadata parser walk the same
        # REXML tree the same way, so the traversal has one definition.
        module ElementText
          module_function

          # @param element [REXML::Element]
          # @return [String] concatenated descendant text
          def collect(element)
            text = +''
            element.each_child do |child|
              case child
              when REXML::Text then text << child.value
              when REXML::Element then text << collect(child)
              end
            end
            text
          end
        end
      end
    end
  end
end
