# frozen_string_literal: true

require 'cgi'
require 'uri'

require_relative '../../base_adapter'

module Shoko
  module Adapters
    module BookSources
      class LibgenClient < Shoko::Adapters::BaseAdapter
        # HTML scraping and normalization helpers for Libgen-compatible pages.
        module HtmlParsing
          private

          def parse_books(html)
            table = extract_table(html)
            return [] unless table

            extract_rows(table).filter_map { |row| parse_row(row) }
          end

          def extract_table(html)
            match = html.to_s.match(%r{<table\b[^>]*\bid\s*=\s*["']tablelibgen["'][^>]*>(.*?)</table>}im)
            match && match[1]
          end

          def extract_rows(table_html)
            source = extract_body(table_html) || table_html.to_s
            source.scan(%r{<tr\b[^>]*>(.*?)</tr>}im).flatten
          end

          def extract_body(table_html)
            match = table_html.to_s.match(%r{<tbody\b[^>]*>(.*?)</tbody>}im)
            match && match[1]
          end

          def parse_row(row_html)
            cells = row_cells(row_html)
            return nil unless cells.length >= 9

            title_link = extract_primary_title_link(cells[0])
            title = title_link && title_link[:text]
            return nil if title.to_s.empty?

            mirrors = row_mirrors(cells[8])
            file_page_url = absolute_url(extract_primary_href(cells[6]))
            md5 = extract_md5(mirrors.first)
            id = preferred_row_id(title_link[:href], file_page_url, md5)
            build_row_payload(cells, id: id, title: title, md5: md5, file_page_url: file_page_url, mirrors: mirrors)
          end

          def row_cells(row_html)
            row_html.to_s.scan(%r{<t[dh]\b[^>]*>(.*?)</t[dh]>}im).flatten
          end

          def row_mirrors(cell_html)
            extract_links(cell_html).first(self.class::MAX_MIRRORS).filter_map { |link| absolute_url(link[:href]) }
          end

          def preferred_row_id(title_href, file_page_url, md5)
            id = extract_id(title_href)
            return id unless id.empty?

            id = extract_id(file_page_url)
            id.empty? ? md5 : id
          end

          def build_row_payload(cells, id:, title:, md5:, file_page_url:, mirrors:)
            {
              id: id,
              title: title,
              authors: extract_people(cells[1]),
              languages: split_values(cells[4]),
              publisher: normalize_text(cells[2]),
              year: normalize_text(cells[3]),
              pages: normalize_text(cells[5]),
              size: normalize_text(extract_primary_link_text(cells[6])),
              extension: normalize_text(cells[7]).downcase,
              md5: md5,
              file_page_url: file_page_url,
              mirrors: mirrors,
            }
          end

          def extract_primary_title_link(cell_html)
            first_line = cell_html.to_s.split(%r{<br\s*/?>}i, 2).first.to_s
            link = extract_links(first_line).find { |candidate| meaningful_title_link?(candidate) }
            link || extract_links(cell_html).find { |candidate| meaningful_title_link?(candidate) }
          end

          def meaningful_title_link?(candidate)
            return false unless candidate

            text = candidate[:text].to_s.strip
            href = candidate[:href].to_s
            return false if text.empty? || text == '↕'

            href.include?('edition.php') || href.include?('book/index.php') || href.include?('id=')
          end

          def extract_primary_link_text(cell_html)
            links = extract_links(cell_html)
            return links.first[:text] unless links.empty?

            cell_html
          end

          def extract_primary_href(cell_html)
            links = extract_links(cell_html)
            links.first && links.first[:href]
          end

          def split_values(cell_html)
            normalize_text(cell_html).split(/[,;]+/).map(&:strip).reject(&:empty?)
          end

          def extract_people(cell_html)
            links = extract_links(cell_html)
            values = if links.empty?
                       split_values(cell_html)
                     else
                       links.map { |link| link[:text].to_s.strip }.reject(&:empty?)
                     end
            values = [normalize_text(cell_html)] if values.empty?
            values.reject(&:empty?)
          end

          def extract_links(html)
            collect_anchor_fragments(html.to_s).filter_map do |attributes, body|
              href = extract_attribute(attributes, 'href')
              next nil if href.to_s.strip.empty?

              {
                href: href,
                text: normalize_text(body),
              }
            end
          end

          def collect_anchor_fragments(html)
            fragments = []
            position = 0
            while (anchor_start = html.index(/<a\b/i, position))
              tag_end = find_tag_end(html, anchor_start + 2)
              break unless tag_end

              close_start = html.index(%r{</a>}i, tag_end + 1)
              break unless close_start

              attributes = html[(anchor_start + 2)...tag_end]
              body = html[(tag_end + 1)...close_start]
              fragments << [attributes, body]
              position = close_start + 4
            end
            fragments
          end

          def find_tag_end(html, start_index)
            quote = nil
            index = start_index
            while index < html.length
              char = html[index]
              if quote
                quote = nil if char == quote
              elsif ['"', "'"].include?(char)
                quote = char
              elsif char == '>'
                return index
              end
              index += 1
            end

            nil
          end

          def extract_attribute(attributes, key)
            match = attributes.to_s.match(/\b#{Regexp.escape(key)}\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i)
            return nil unless match

            match.captures.compact.first
          end

          def extract_id(href)
            query_value(uri_query(absolute_url(href)), 'id').to_s
          end

          def extract_md5(url)
            return '' if url.to_s.strip.empty?

            query_value(uri_query(url), 'md5').to_s
          end

          def absolute_url(href)
            return nil if href.to_s.strip.empty?

            safe_normalize_uri(href, base: @base_url)&.to_s
          end

          def extract_download_href(html)
            extract_links(html).each do |link|
              href = link[:href].to_s
              return href if direct_download_href?(href)
            end

            raise Error, 'No download links found on mirror page'
          end

          def direct_download_href?(href)
            href.match?(%r{(?:^|/)(?:get|download|file\.php)\b}i) || href.include?('get=') || href.include?('download=')
          end

          def normalize_text(text)
            decoded = CGI.unescapeHTML(text.to_s.gsub(/<[^>]+>/, ' '))
            decoded.gsub(/\s+/, ' ').strip
          end

          def query_value(query, key)
            URI.decode_www_form(query.to_s).each do |pair_key, pair_value|
              return pair_value if pair_key == key
            end

            nil
          end
        end
      end
    end
  end
end
