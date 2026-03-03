# frozen_string_literal: true

require 'cgi'

require_relative '../../../shared/text_sanitizer'

module Shoko
  module Core
    module BookFormats
      module Epub
        # Processes HTML content
        class HTMLProcessor
          def self.extract_title(html)
            match = html.match(%r{<title[^>]*>([^<]+)</title>}i) ||
                    html.match(%r{<h[1-3][^>]*>([^<]+)</h[1-3]>}i)
            clean_html(match[1]) if match
          end

          def self.html_to_text(html)
            normalize_html(html)
          end

          BLOCK_REPLACEMENTS = {
            %r{</p>}i => "\n\n",
            /<p[^>]*>/i => "\n\n",
            /<br[^>]*>/i => "\n",
            %r{</h[1-6]>}i => "\n\n",
            /<h[1-6][^>]*>/i => "\n\n",
            %r{</div>}i => "\n",
            /<div[^>]*>/i => "\n",
          }.freeze

          private_constant :BLOCK_REPLACEMENTS

          HTML_ENTITY_MAP = {
            'nbsp' => ' ',
            'ensp' => ' ',
            'emsp' => ' ',
            'thinsp' => ' ',
            'shy' => '',
            'mdash' => '—',
            'ndash' => '–',
            'hellip' => '…',
            'ldquo' => "\u201C",
            'rdquo' => "\u201D",
            'lsquo' => "\u2018",
            'rsquo' => "\u2019",
            'laquo' => '«',
            'raquo' => '»',
            'bull' => '•',
            'middot' => '·',
            'times' => '×',
            'divide' => '÷',
            'deg' => '°',
            'copy' => '©',
            'reg' => '®',
            'trade' => '™',
            'frac14' => '¼',
            'frac12' => '½',
            'frac34' => '¾',
            'sup1' => '¹',
            'sup2' => '²',
            'sup3' => '³',
          }.freeze

          private_constant :HTML_ENTITY_MAP

          def self.decode_entities(text)
            str = text.to_s
            return str if str.empty?

            decoded = str.gsub(/&#x([0-9A-Fa-f]+);/) do |match|
              [Regexp.last_match(1).to_i(16)].pack('U')
            rescue Shoko::Error
              match
            end

            decoded = decoded.gsub(/&#(\d+);/) do |match|
              [Regexp.last_match(1).to_i].pack('U')
            rescue Shoko::Error
              match
            end

            decoded = decoded.gsub(/&([A-Za-z][A-Za-z0-9]+);/) do |match|
              name = Regexp.last_match(1)
              replacement = HTML_ENTITY_MAP[name] || HTML_ENTITY_MAP[name.downcase]
              replacement.nil? ? match : replacement
            end

            # Decode the built-in XML entities (amp/lt/gt/quot/apos) last.
            CGI.unescapeHTML(decoded).tr("\u00A0", ' ')
          end

          private_class_method def self.normalize_html(html)
            text = html.dup
            # Handle CDATA sections BEFORE removing other tags
            text = handle_cdata_sections(text)
            text = remove_scripts_and_styles(text)
            text = replace_block_elements(text)
            text = strip_tags(text)
            text = decode_entities(text)
            cleaned = clean_whitespace(text)
            Shoko::Shared::TextSanitizer.sanitize(
              cleaned,
              preserve_newlines: true,
              preserve_tabs: false
            )
          end

          private_class_method def self.handle_cdata_sections(text)
            # Extract CDATA content before other processing
            text.gsub(/<!\[CDATA\[(.*?)\]\]>/m, '\1')
          end

          private_class_method def self.remove_scripts_and_styles(text)
            text.gsub!(%r{<script[^>]*>.*?</script>}mi, '')
            text.gsub!(%r{<style[^>]*>.*?</style>}mi, '')
            text
          end

          private_class_method def self.replace_block_elements(text)
            BLOCK_REPLACEMENTS.each { |pattern, rep| text.gsub!(pattern, rep) }
            text
          end

          private_class_method def self.strip_tags(text)
            text.gsub!(/<[^>]+>/, '')
            text
          end

          private_class_method def self.clean_whitespace(text)
            text.delete!("\r")
            text.gsub!(/\n{3,}/, "\n\n")
            text.gsub!(/[ \t]+/, ' ')
            text.strip
          end

          def self.clean_html(text)
            decoded = decode_entities(text.to_s.strip)
            Shoko::Shared::TextSanitizer.sanitize(
              decoded,
              preserve_newlines: false,
              preserve_tabs: false
            )
          end
        end
      end
    end
  end
end
