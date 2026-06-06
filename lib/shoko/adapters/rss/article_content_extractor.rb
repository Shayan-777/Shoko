# frozen_string_literal: true

require_relative '../base_adapter'
require_relative '../book_sources/epub/parser/html_processor'

module Shoko
  module Adapters
    module Rss
      # Extracts readable article text from a fetched HTML page.
      class ArticleContentExtractor < Shoko::Adapters::BaseAdapter
        CANDIDATE_CONTAINERS = [
          { tag: 'section', class_name: 'body' },
          { tag: 'div', class_name: 'entry-content' },
          { tag: 'div', class_name: 'post-content' },
          { tag: 'div', class_name: 'article-content' },
          { tag: 'div', class_name: 'post-body' },
          { tag: 'div', class_name: 'content-body' },
          { tag: 'div', class_name: 'markdown-body' },
          { tag: 'article', class_name: nil },
          { tag: 'main', class_name: nil },
          { tag: 'body', class_name: nil },
        ].freeze

        # Site chrome that surrounds the article. Removed before container selection so
        # the body fallback yields the post instead of navigation and sitemap links.
        BOILERPLATE_TAGS = %w[script style noscript template nav header footer aside form].freeze

        def extract(html)
          source = html.to_s
          return '' if source.strip.empty?

          fragment = select_best_fragment(strip_boilerplate(source))
          normalize_text(fragment)
        end

        private

        def strip_boilerplate(source)
          BOILERPLATE_TAGS.reduce(source) { |html, tag| remove_elements(html, tag) }
        end

        def remove_elements(source, tag_name)
          result = source
          while (start_tag = find_start_tag(result, tag_name, nil))
            offset = start_tag[:offset]
            block = balanced_tag_content(result, offset, tag_name)
            result = result[0...offset] + result[(offset + block.length)..].to_s
          end
          result
        end

        def select_best_fragment(source)
          CANDIDATE_CONTAINERS.each do |candidate|
            fragment = extract_container(source, candidate[:tag], candidate[:class_name])
            return fragment if fragment && !fragment.strip.empty?
          end

          source
        end

        def extract_container(source, tag_name, class_name)
          start_tag = find_start_tag(source, tag_name, class_name)
          return nil unless start_tag

          balanced_tag_content(source, start_tag[:offset], tag_name)
        end

        def find_start_tag(source, tag_name, class_name)
          source.to_enum(:scan, /<#{tag_name}\b[^>]*>/im).filter_map do
            match = Regexp.last_match
            tag = match[0]
            next if class_name && !class_attribute_matches?(tag, class_name)

            { offset: match.begin(0), text: tag }
          end.first
        end

        def class_attribute_matches?(tag, class_name)
          match = tag.match(/\bclass\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i)
          return false unless match

          classes = [match[1], match[2], match[3]].compact.first.to_s.split(/\s+/)
          classes.include?(class_name)
        end

        def balanced_tag_content(source, offset, tag_name)
          depth = 0
          scanner = %r{</?#{tag_name}\b[^>]*>}im
          source[offset..].to_enum(:scan, scanner).each do
            match = Regexp.last_match
            depth += closing_tag?(match[0]) ? -1 : 1
            next unless depth.zero?

            finish = offset + match.end(0)
            return source[offset...finish]
          end

          source[offset..]
        end

        def closing_tag?(tag)
          tag.start_with?('</')
        end

        def normalize_text(fragment)
          text = Shoko::Adapters::BookSources::Epub::HTMLProcessor.html_to_text(fragment.to_s)
          text.to_s.gsub(/\n{3,}/, "\n\n").strip
        end
      end
    end
  end
end
