# frozen_string_literal: true

require 'rexml/document'

module Shoko
  module Core
    module BookFormats
      module Epub
        # Extracts href and cleaned label text from a nav list item.
        class OPFNavigationListItem
          def initialize(list_item, cleaner:)
            @list_item = list_item
            @cleaner = cleaner
            @empty_text = ''
          end

          def href
            anchor&.attributes&.[]('href')
          end

          def title
            return clean_text(anchor.texts.join) if anchor

            clean_text(list_item_text)
          end

          private

          def clean_text(text)
            @cleaner.clean_label(text)
          end

          def anchor
            @anchor ||= begin
              elements = @list_item.elements
              elements['./*[local-name()="a"]'] || elements['.//*[local-name()="a"]']
            end
          end

          def list_item_text
            stop_element = list_container_element
            @list_item.children.take_while { |child| child != stop_element }.each_with_object(+'') do |child, buffer|
              buffer << node_text(child)
            end
          end

          def list_container_element
            @list_item.elements['./*[local-name()="ol" or local-name()="ul"]']
          end

          def node_text(child)
            text = child.to_s
            text.empty? ? @empty_text : text
          end
        end
      end
    end
  end
end
