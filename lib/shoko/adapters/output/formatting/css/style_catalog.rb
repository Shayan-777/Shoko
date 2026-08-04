# frozen_string_literal: true

require_relative 'stylesheet_parser'
require_relative 'element_style_resolver'

module Shoko
  module Adapters
    module Output
      module Formatting
        module Css
          # Book-level stylesheet store. Holds the raw CSS texts extracted at
          # import time (keyed by archive path), compiles each sheet once on
          # first use, and builds per-chapter ElementStyleResolvers from the
          # chapter's <link> references plus its inline <style> blocks.
          #
          # Kindle books carry their CSS in document <style> blocks with no
          # per-chapter links; `apply_all_sheets: true` applies every catalog
          # sheet to every chapter for that case.
          class StyleCatalog
            LINK_PATTERN = /<link\b[^>]*>/i
            HREF_PATTERN = /href\s*=\s*["']([^"']+)["']/i
            REL_STYLESHEET_PATTERN = /rel\s*=\s*["'][^"']*stylesheet[^"']*["']/i
            STYLE_BLOCK_PATTERN = %r{<style\b[^>]*>(.*?)</style>}mi

            def initialize(stylesheets: {}, apply_all_sheets: false, logger: nil)
              @stylesheets = normalize_stylesheets(stylesheets)
              @apply_all_sheets = apply_all_sheets ? true : false
              @logger = logger
              @compiled_sheets = {}
              # The catalog is shared by the UI thread and the reader's
              # background worker (via the formatting service singleton), so the
              # compile memo is serialized.
              @compile_mutex = Mutex.new
            end

            def any_stylesheets?
              !@stylesheets.empty?
            end

            # @param chapter_source_path [String, nil] archive path of the chapter
            # @param raw_content [String] the chapter's raw (X)HTML
            # @return [ElementStyleResolver, nil] nil when no styles apply
            def resolver_for(chapter_source_path:, raw_content:)
              raw = raw_content.to_s
              sheet_paths = sheet_paths_for(chapter_source_path, raw)
              inline_sources = inline_style_sources(raw)
              return nil if sheet_paths.empty? && inline_sources.empty?

              rules = combined_rules(sheet_paths, inline_sources)
              return nil if rules.empty?

              ElementStyleResolver.new(rules: rules)
            # resilient-boundary
            rescue StandardError => e
              swallow_resolver_error(e, chapter_source_path)
            end

            private

            def swallow_resolver_error(error, chapter_source_path)
              @logger&.warn('style_catalog.resolver_build_failed',
                            error: error.class.name,
                            message: error.message,
                            chapter: chapter_source_path.to_s)
              nil
            end

            def normalize_stylesheets(stylesheets)
              (stylesheets || {}).each_with_object({}) do |(path, text), acc|
                normalized = normalize_path(path.to_s)
                acc[normalized] = text.to_s unless normalized.empty? || text.to_s.empty?
              end
            end

            def sheet_paths_for(chapter_source_path, raw)
              return @stylesheets.keys if @apply_all_sheets
              return [] if @stylesheets.empty?

              linked_sheet_paths(chapter_source_path, raw)
            end

            def linked_sheet_paths(chapter_source_path, raw)
              base_dir = File.dirname(chapter_source_path.to_s)
              raw.scan(LINK_PATTERN).filter_map do |link_tag|
                next unless REL_STYLESHEET_PATTERN.match?(link_tag) || link_tag !~ /rel\s*=/i

                href = link_tag[HREF_PATTERN, 1]
                next if href.nil? || href.empty?

                resolved = resolve_href(base_dir, href)
                resolved if @stylesheets.key?(resolved)
              end
            end

            def resolve_href(base_dir, href)
              cleaned = href.split(/[?#]/, 2).first.to_s
              normalize_path(File.expand_path(File.join('/', base_dir, cleaned), '/'))
            end

            def normalize_path(path)
              path.sub(%r{\A/+}, '')
            end

            def inline_style_sources(raw)
              raw.scan(STYLE_BLOCK_PATTERN).filter_map do |(content)|
                text = content.to_s.gsub(/<!\[CDATA\[|\]\]>|<!--|-->/, ' ').strip
                text unless text.empty?
              end
            end

            def combined_rules(sheet_paths, inline_sources)
              rules = sheet_paths.flat_map { |path| compiled_sheet(path) }
              inline_sources.each { |css| rules += StylesheetParser.parse(css) }
              reindex_rules(rules)
            end

            # Rule order indexes are per-sheet; renumber so later sheets (and
            # inline blocks) cascade over earlier ones at equal specificity.
            def reindex_rules(rules)
              rules.each_with_index.map do |rule, index|
                StylesheetParser::Rule.new(
                  selector: rule.selector,
                  declarations: rule.declarations,
                  specificity: rule.specificity,
                  order: index
                )
              end
            end

            def compiled_sheet(path)
              @compile_mutex.synchronize do
                @compiled_sheets[path] ||= StylesheetParser.parse(@stylesheets[path])
              end
            end
          end
        end
      end
    end
  end
end
