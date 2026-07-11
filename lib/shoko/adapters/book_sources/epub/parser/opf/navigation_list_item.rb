# frozen_string_literal: true

require 'rexml/document'

require_relative 'element_queries'

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Extracts href and cleaned label text from a nav list item.
        class OPFNavigationListItem
          include OPFElementQueries

          LIST_CONTAINER_TAGS = %w[ol ul].freeze
          private_constant :LIST_CONTAINER_TAGS

          def initialize(list_item, cleaner:)
            @list_item = list_item
            @cleaner = cleaner
            @empty_text = ''
          end

          def href
            attribute_value(anchor, 'href')
          end

          def title
            return clean_text(anchor.to_s) if anchor

            clean_text(list_item_text)
          end

          private

          def clean_text(text)
            @cleaner.clean_label(text)
          end

          def anchor
            @anchor ||= first_child_element_named(@list_item, 'a') ||
                        first_descendant_element_named(@list_item, 'a')
          end

          def list_item_text
            stop_element = list_container_element
            @list_item.children.take_while { |child| child != stop_element }.each_with_object(+'') do |child, buffer|
              buffer << node_text(child)
            end
          end

          def list_container_element
            first_child_element_named(@list_item, *LIST_CONTAINER_TAGS)
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
