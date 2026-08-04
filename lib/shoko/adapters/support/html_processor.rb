# frozen_string_literal: true

require 'cgi'

require 'shoko/shared/text_sanitizer'

module Shoko
  module Adapters
    module Support
      # Processes HTML content
      class HTMLProcessor
        def self.extract_title(html)
          match = html.match(%r{<title[^>]*>(.*?)</title>}im) ||
                  html.match(%r{<h[1-3][^>]*>(.*?)</h[1-3]>}im)
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

        WHITESPACE_ENTITIES = {
          'nbsp' => ' ', 'ensp' => ' ', 'emsp' => ' ', 'thinsp' => ' ',
          'shy' => '', 'zwnj' => '', 'zwj' => '', 'lrm' => '', 'rlm' => ''
        }.freeze

        PUNCTUATION_ENTITIES = {
          'mdash' => '—', 'ndash' => '–', 'horbar' => '―', 'hellip' => '…',
          'ldquo' => '“', 'rdquo' => '”', 'lsquo' => '‘', 'rsquo' => '’',
          'sbquo' => '‚', 'bdquo' => '„', 'laquo' => '«', 'raquo' => '»',
          'lsaquo' => '‹', 'rsaquo' => '›', 'bull' => '•', 'middot' => '·',
          'dagger' => '†', 'Dagger' => '‡', 'permil' => '‰', 'prime' => '′', 'Prime' => '″',
          'oline' => '‾', 'frasl' => '⁄', 'iexcl' => '¡', 'iquest' => '¿',
          'sect' => '§', 'para' => '¶', 'uml' => '¨', 'acute' => '´', 'cedil' => '¸',
          'macr' => '¯', 'circ' => 'ˆ', 'tilde' => '˜', 'brvbar' => '¦'
        }.freeze

        SYMBOL_ENTITIES = {
          'times' => '×', 'divide' => '÷', 'deg' => '°', 'copy' => '©', 'reg' => '®',
          'trade' => '™', 'euro' => '€', 'cent' => '¢', 'pound' => '£', 'yen' => '¥',
          'curren' => '¤', 'fnof' => 'ƒ', 'micro' => 'µ', 'ordf' => 'ª', 'ordm' => 'º',
          'frac14' => '¼', 'frac12' => '½', 'frac34' => '¾',
          'sup1' => '¹', 'sup2' => '²', 'sup3' => '³',
          'plusmn' => '±', 'minus' => '−', 'lowast' => '∗', 'not' => '¬',
          'le' => '≤', 'ge' => '≥', 'ne' => '≠', 'equiv' => '≡', 'asymp' => '≈',
          'infin' => '∞', 'radic' => '√', 'sum' => '∑', 'prod' => '∏', 'int' => '∫',
          'part' => '∂', 'nabla' => '∇', 'isin' => '∈', 'notin' => '∉', 'ni' => '∋',
          'cap' => '∩', 'cup' => '∪', 'forall' => '∀', 'exist' => '∃', 'empty' => '∅',
          'and' => '∧', 'or' => '∨', 'there4' => '∴', 'sim' => '∼', 'cong' => '≅',
          'prop' => '∝', 'perp' => '⊥', 'ang' => '∠', 'oplus' => '⊕', 'otimes' => '⊗',
          'sdot' => '⋅', 'lceil' => '⌈', 'rceil' => '⌉', 'lfloor' => '⌊', 'rfloor' => '⌋',
          'larr' => '←', 'uarr' => '↑', 'rarr' => '→', 'darr' => '↓', 'harr' => '↔',
          'crarr' => '↵', 'lArr' => '⇐', 'uArr' => '⇑', 'rArr' => '⇒', 'dArr' => '⇓',
          'hArr' => '⇔', 'loz' => '◊', 'spades' => '♠', 'clubs' => '♣',
          'hearts' => '♥', 'diams' => '♦'
        }.freeze

        LATIN_ENTITIES = {
          'Agrave' => 'À', 'Aacute' => 'Á', 'Acirc' => 'Â', 'Atilde' => 'Ã', 'Auml' => 'Ä',
          'Aring' => 'Å', 'AElig' => 'Æ', 'Ccedil' => 'Ç', 'Egrave' => 'È', 'Eacute' => 'É',
          'Ecirc' => 'Ê', 'Euml' => 'Ë', 'Igrave' => 'Ì', 'Iacute' => 'Í', 'Icirc' => 'Î',
          'Iuml' => 'Ï', 'ETH' => 'Ð', 'Ntilde' => 'Ñ', 'Ograve' => 'Ò', 'Oacute' => 'Ó',
          'Ocirc' => 'Ô', 'Otilde' => 'Õ', 'Ouml' => 'Ö', 'Oslash' => 'Ø', 'Ugrave' => 'Ù',
          'Uacute' => 'Ú', 'Ucirc' => 'Û', 'Uuml' => 'Ü', 'Yacute' => 'Ý', 'THORN' => 'Þ',
          'szlig' => 'ß', 'agrave' => 'à', 'aacute' => 'á', 'acirc' => 'â', 'atilde' => 'ã',
          'auml' => 'ä', 'aring' => 'å', 'aelig' => 'æ', 'ccedil' => 'ç', 'egrave' => 'è',
          'eacute' => 'é', 'ecirc' => 'ê', 'euml' => 'ë', 'igrave' => 'ì', 'iacute' => 'í',
          'icirc' => 'î', 'iuml' => 'ï', 'eth' => 'ð', 'ntilde' => 'ñ', 'ograve' => 'ò',
          'oacute' => 'ó', 'ocirc' => 'ô', 'otilde' => 'õ', 'ouml' => 'ö', 'oslash' => 'ø',
          'ugrave' => 'ù', 'uacute' => 'ú', 'ucirc' => 'û', 'uuml' => 'ü', 'yacute' => 'ý',
          'thorn' => 'þ', 'yuml' => 'ÿ', 'OElig' => 'Œ', 'oelig' => 'œ',
          'Scaron' => 'Š', 'scaron' => 'š', 'Yuml' => 'Ÿ'
        }.freeze

        GREEK_ENTITIES = {
          'Alpha' => 'Α', 'Beta' => 'Β', 'Gamma' => 'Γ', 'Delta' => 'Δ', 'Epsilon' => 'Ε',
          'Zeta' => 'Ζ', 'Eta' => 'Η', 'Theta' => 'Θ', 'Iota' => 'Ι', 'Kappa' => 'Κ',
          'Lambda' => 'Λ', 'Mu' => 'Μ', 'Nu' => 'Ν', 'Xi' => 'Ξ', 'Omicron' => 'Ο',
          'Pi' => 'Π', 'Rho' => 'Ρ', 'Sigma' => 'Σ', 'Tau' => 'Τ', 'Upsilon' => 'Υ',
          'Phi' => 'Φ', 'Chi' => 'Χ', 'Psi' => 'Ψ', 'Omega' => 'Ω',
          'alpha' => 'α', 'beta' => 'β', 'gamma' => 'γ', 'delta' => 'δ', 'epsilon' => 'ε',
          'zeta' => 'ζ', 'eta' => 'η', 'theta' => 'θ', 'iota' => 'ι', 'kappa' => 'κ',
          'lambda' => 'λ', 'mu' => 'μ', 'nu' => 'ν', 'xi' => 'ξ', 'omicron' => 'ο',
          'pi' => 'π', 'rho' => 'ρ', 'sigmaf' => 'ς', 'sigma' => 'σ', 'tau' => 'τ',
          'upsilon' => 'υ', 'phi' => 'φ', 'chi' => 'χ', 'psi' => 'ψ', 'omega' => 'ω',
          'thetasym' => 'ϑ', 'upsih' => 'ϒ', 'piv' => 'ϖ'
        }.freeze

        HTML_ENTITY_MAP = WHITESPACE_ENTITIES
                          .merge(PUNCTUATION_ENTITIES)
                          .merge(SYMBOL_ENTITIES)
                          .merge(LATIN_ENTITIES)
                          .merge(GREEK_ENTITIES)
                          .freeze

        private_constant :WHITESPACE_ENTITIES, :PUNCTUATION_ENTITIES, :SYMBOL_ENTITIES,
                         :LATIN_ENTITIES, :GREEK_ENTITIES, :HTML_ENTITY_MAP

        def self.decode_entities(text)
          str = text.to_s
          return str if str.empty?

          decoded = str.gsub(/&#x([0-9A-Fa-f]+);/) do |_match|
            [Regexp.last_match(1).to_i(16)].pack('U')
          end

          decoded = decoded.gsub(/&#(\d+);/) do |_match|
            [Regexp.last_match(1).to_i].pack('U')
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
          Shoko::Shared::TextSanitizer.sanitize(cleaned, preserve_newlines: true, preserve_tabs: false)
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
          cleaned = normalize_html(text.to_s)
          inline = cleaned.gsub(/\s+/, ' ').strip
          Shoko::Shared::TextSanitizer.sanitize(inline, preserve_newlines: false, preserve_tabs: false)
        end
      end
    end
  end
end
