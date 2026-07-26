# frozen_string_literal: true

require 'time'

require_relative '../../shared/text_sanitizer'
require_relative 'article_block_parser'
require_relative '../../shared/errors'
require_relative '../book_sources/epub/parser/html_processor'
require_relative '../book_sources/epub/parser/rexml_safe_parser'

module Shoko
  module Adapters
    module Rss
      # Parses RSS/Atom feed XML into normalized feed/article hashes.
      class FeedParser
        class ParseError < Shoko::Error; end

        def parse(xml)
          safe_xml = Shoko::Shared::TextSanitizer.sanitize_xml_source(xml.to_s,
                                                                      preserve_newlines: true,
                                                                      preserve_tabs: false)
          document = Shoko::Adapters::BookSources::Epub::REXMLSafeParser.parse(safe_xml)
          parse_document(document)
        rescue REXML::ParseException => e
          raise ParseError, "Invalid feed XML: #{e.message}"
        end

        private

        def parse_document(document)
          root = document.root
          raise ParseError, 'Feed payload is empty' unless root

          parse_root(root)
        end

        def parse_root(root)
          case local_name(root.name)
          when 'rss' then parse_rss(root)
          when 'RDF' then parse_rdf(root)
          when 'feed' then parse_atom(root)
          else raise ParseError, "Unsupported feed root: #{root.name}"
          end
        end

        def parse_rss(root)
          channel = first_child(root, 'channel')
          raise ParseError, 'RSS channel element is missing' unless channel

          {
            title: clean_inline_text(child_text(channel, 'title')),
            site_url: clean_url(child_text(channel, 'link')),
            articles: child_elements(channel, 'item').filter_map { |item| parse_rss_item(item) },
          }
        end

        def parse_rdf(root)
          channel = first_child(root, 'channel')
          {
            title: clean_inline_text(channel && child_text(channel, 'title')),
            site_url: clean_url(channel && child_text(channel, 'link')),
            articles: child_elements(root, 'item').filter_map { |item| parse_rss_item(item) },
          }
        end

        def parse_atom(root)
          {
            title: clean_inline_text(child_text(root, 'title')),
            site_url: clean_url(atom_link(root)),
            articles: child_elements(root, 'entry').filter_map { |entry| parse_atom_entry(entry) },
          }
        end

        def parse_rss_item(item)
          build_article_payload(
            title: clean_inline_text(child_text(item, 'title')),
            url: clean_url(rss_item_link(item)),
            guid: clean_inline_text(child_text(item, 'guid')),
            author: clean_inline_text(child_text(item, 'author', 'creator')),
            summary: clean_block_text(child_text(item, 'description', 'summary')),
            content: clean_block_text(child_text(item, 'content:encoded', 'encoded', 'content')),
            content_blocks: parse_blocks(child_text(item, 'content:encoded', 'encoded', 'content'),
                                         child_text(item, 'description', 'summary')),
            published_at: parse_time(child_text(item, 'pubDate', 'date', 'published'))
          )
        end

        def parse_atom_entry(entry)
          build_article_payload(
            title: clean_inline_text(child_text(entry, 'title')),
            url: clean_url(atom_link(entry)),
            guid: clean_inline_text(child_text(entry, 'id')),
            author: clean_inline_text(atom_author(entry)),
            summary: clean_block_text(child_text(entry, 'summary')),
            content: clean_block_text(child_text(entry, 'content')),
            content_blocks: parse_blocks(child_text(entry, 'content'), child_text(entry, 'summary')),
            published_at: parse_time(child_text(entry, 'published', 'updated'))
          )
        end

        def build_article_payload(title:, url:, guid:, author:, summary:, content:, content_blocks:, published_at:)
          return nil if article_payload_empty?(title: title, url: url, summary: summary)

          {
            title: title.empty? ? fallback_title(summary, url) : title,
            url: url,
            guid: presence(guid),
            author: presence(author),
            summary: summary,
            content: content,
            content_blocks: content_blocks,
            published_at: published_at,
          }
        end

        def article_payload_empty?(title:, url:, summary:)
          title.empty? && url.to_s.empty? && summary.empty?
        end

        def presence(value)
          text = value.to_s.strip
          return nil if text.empty?

          text
        end

        def rss_item_link(item)
          link = child_text(item, 'link')
          return link unless link.to_s.strip.empty?

          guid_element = first_child(item, 'guid')
          return nil unless guid_element

          return guid_element.text.to_s if guid_element.attributes['isPermaLink'].to_s.downcase == 'true'

          nil
        end

        def atom_link(element)
          links = child_elements(element, 'link')
          chosen = links.find do |link|
            rel = link.attributes['rel'].to_s.strip.downcase
            rel.empty? || rel == 'alternate'
          end
          chosen ||= links.first
          href = chosen&.attributes&.[]('href')
          href.to_s.strip.empty? ? child_text(chosen, 'href') : href
        end

        def atom_author(entry)
          author = first_child(entry, 'author')
          return nil unless author

          child_text(author, 'name')
        end

        def child_text(element, *candidates)
          child = first_child(element, *candidates)
          return nil unless child

          node_content(child)
        end

        def first_child(element, *candidates)
          return nil unless element

          names = candidates.flatten.map { |name| normalize_name(name) }
          element.elements.find do |child|
            match_name?(child, names)
          end
        end

        def child_elements(element, *candidates)
          return [] unless element

          names = candidates.flatten.map { |name| normalize_name(name) }
          element.elements.select { |child| match_name?(child, names) }
        end

        def match_name?(element, names)
          name = normalize_name(element.name)
          names.include?(name) || names.include?(local_name(name))
        end

        def normalize_name(name)
          name.to_s.strip
        end

        def local_name(name)
          name.to_s.split(':').last.to_s
        end

        def node_content(node)
          text = if node.has_elements?
                   node.children.join
                 else
                   node.text.to_s
                 end
          text.to_s
        end

        # The feed's own HTML is the only structure available for entries whose
        # linked page is never fetched, so it is parsed rather than flattened.
        # Falls back to the description when there is no full content element.
        def parse_blocks(content_html, summary_html)
          source = content_html.to_s.strip
          source = summary_html.to_s if source.empty?
          return [] if source.strip.empty?

          block_parser.parse(source)
        end

        def block_parser
          @block_parser ||= ArticleBlockParser.new
        end

        def clean_inline_text(value)
          text = Shoko::Adapters::BookSources::Epub::HTMLProcessor.html_to_text(value.to_s)
          Shoko::Shared::TextSanitizer.sanitize(text, preserve_newlines: false, preserve_tabs: false).strip
        end

        def clean_block_text(value)
          text = Shoko::Adapters::BookSources::Epub::HTMLProcessor.html_to_text(value.to_s)
          sanitized = Shoko::Shared::TextSanitizer.sanitize(text, preserve_newlines: true, preserve_tabs: false)
          sanitized.gsub(/\n{3,}/, "\n\n").strip
        end

        def clean_url(value)
          text = value.to_s.strip
          return nil if text.empty?

          text
        end

        def parse_time(value)
          text = value.to_s.strip
          return nil if text.empty?

          Time.parse(text).utc.iso8601
        rescue ArgumentError
          invalid_time_value
        end

        def invalid_time_value
          nil
        end

        def fallback_title(summary, url)
          summary_line = summary.to_s.lines.first.to_s.strip
          return summary_line unless summary_line.empty?

          url.to_s.strip.empty? ? 'Untitled Article' : url.to_s.strip
        end
      end
    end
  end
end
