# frozen_string_literal: true

require 'rexml/document'

require_relative 'navigation_label_resolver'
require_relative 'navigation_list_item'

module Shoko
  module Core
    module BookFormats
      module Epub
        # Tracks navigation entries/titles while walking a nav tree.
        class OPFNavigationContext
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
            elements = nav_point.elements
            href_attr = elements['content']&.attributes&.[]('src')
            title = resolve_label(
              href: href_attr,
              title: clean_label(elements['navLabel/text']&.text.to_s)
            )
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
        end
      end
    end
  end
end
