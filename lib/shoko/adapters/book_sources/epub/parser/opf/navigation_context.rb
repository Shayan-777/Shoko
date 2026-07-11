# frozen_string_literal: true

require 'rexml/document'

require_relative 'element_queries'
require_relative 'navigation_label_resolver'
require_relative 'navigation_list_item'

module Shoko
  module Adapters
    module BookSources
      module Epub
        # Tracks navigation entries/titles while walking a nav tree.
        class OPFNavigationContext
          include OPFElementQueries

          attr_reader :toc_entries, :titles, :level

          def self.root(source_path:, entry_reader:)
            label_resolver = OPFNavigationLabelResolver.new(entry_reader: entry_reader, source_path: source_path)
            new(label_resolver: label_resolver, level: 0, toc_entries: [], titles: {})
          end

          def initialize(label_resolver:, level:, toc_entries:, titles:)
            @label_resolver = label_resolver
            @level = level
            @toc_entries = toc_entries
            @titles = titles
          end

          def source_path
            @label_resolver.source_path
          end

          def next_level
            self.class.new(
              label_resolver: @label_resolver,
              level: @level + 1,
              toc_entries: @toc_entries,
              titles: @titles
            )
          end

          def add_entry(title:, href:)
            target_path, opf_href = @label_resolver.target_for(href: href)
            @toc_entries << {
              title: title,
              href: href,
              level: @level,
              source_path: source_path,
              target: target_path,
              opf_href: opf_href,
            }

            return unless opf_href
            return if @level.zero? && @titles.key?(opf_href)

            @titles[opf_href] = title
          end

          def clean_label(text)
            @label_resolver.clean_label(text)
          end

          def resolve_label(href:, title:)
            @label_resolver.resolve(href: href, title: title)
          end

          def entry_for_nav_point(nav_point)
            content = first_child_element_named(nav_point, 'content')
            href_attr = attribute_value(content, 'src')
            title = resolve_label(href: href_attr, title: clean_label(nav_point_label_text(nav_point)))
            [title, href_attr]
          end

          def entry_for_list_item(list_item)
            details = OPFNavigationListItem.new(list_item, cleaner: self)
            href_attr = details.href
            title = resolve_label(href: href_attr, title: details.title)
            [title, href_attr]
          end

          def to_result(result_class)
            result_class.new(toc_entries: @toc_entries, titles: @titles)
          end

          private

          def nav_point_label_text(nav_point)
            nav_label = first_child_element_named(nav_point, 'navLabel')
            text = first_child_element_named(nav_label, 'text')
            text&.text.to_s
          end
        end
      end
    end
  end
end
