# frozen_string_literal: true

require 'rexml/document'

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Walks nav/NCX trees to populate navigation context entries.
        class OPFNavigationWalker
          def initialize(context)
            @context = context
            @list_item_tag = 'li'
            @list_container_tags = %w[ol ul]
          end

          def walk_nav_points(node)
            node.each_element('navPoint') do |nav_point|
              title, href = @context.entry_for_nav_point(nav_point)
              @context.add_entry(title: title, href: href)
              self.class.new(@context.next_level).walk_nav_points(nav_point)
            end
          end

          def walk_nav_list(list)
            list.each_element do |child|
              next unless child.is_a?(REXML::Element) && child.name.casecmp(@list_item_tag).zero?

              process_list_item(child)
            end
          end

          private

          def process_list_item(child)
            title, href = @context.entry_for_list_item(child)
            @context.add_entry(title: title, href: href)
            walk_nested_list(child)
          end

          def walk_nested_list(child)
            nested = nested_list(child)
            return unless nested

            self.class.new(@context.next_level).walk_nav_list(nested)
          end

          def nested_list(child)
            elements = child.elements
            @list_container_tags.each do |tag|
              list = elements["./*[local-name()=\"#{tag}\"]"]
              return list if list
            end
            nil
          end
        end
      end
    end
  end
end
