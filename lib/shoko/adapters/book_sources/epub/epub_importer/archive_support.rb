# frozen_string_literal: true

module Shoko
  module Adapters
    module BookSources
      module Epub
        class EpubImporter
          # Archive access, entry reads, and OPF location helpers.
          module ArchiveSupport
            private

            def read_container(zip)
              instrument('epub.read_container') do
                normalize_text(zip.read(CONTAINER_PATH))
              end
            rescue Zip::Error
              raise Shoko::BookParseError.new('Missing META-INF/container.xml', @epub_path)
            end

            def locate_opf_path(zip, container_xml)
              located = instrument('epub.locate_opf') do
                rootfile_candidate(zip, container_xml)
              end
              return located if located

              matched = matching_container_path(zip, container_xml)
              return matched if matched

              raise Shoko::BookParseError.new('Unable to locate OPF file', @epub_path)
            rescue REXML::ParseException => e
              raise Shoko::BookParseError.new("Invalid container.xml: #{e.message}", @epub_path)
            end

            def rootfile_candidate(zip, container_xml)
              doc = Adapters::BookSources::Epub::REXMLSafeParser.parse(container_xml)
              elems = doc.elements
              rootfile = elems['//rootfile'] || elems['//container:rootfile']
              candidate = rootfile&.attributes&.[]('full-path')
              candidate if candidate && zip.find_entry(candidate)
            end

            def matching_container_path(zip, container_xml)
              match = container_xml.to_s.match(/full-path=["']([^"']+)["']/i)
              candidate = match && match[1]
              candidate if candidate && zip.find_entry(candidate)
            end

            def extract_resources(zip, opf_path, manifest)
              manifest.each_with_object({}) do |(_, href), resources|
                path = resolved_manifest_path(opf_path, href)
                next unless path && zip.find_entry(path)

                resources[path] = read_binary_entry(zip, path)
              end
            end

            def resolved_manifest_path(opf_path, href)
              rel = href.to_s
              return nil if rel.empty?

              resolve_href(opf_path, rel)
            end

            def read_text_entry(zip, path)
              instrument('epub.read_text_entry') do
                content = zip.read(path)
                normalize_text(content)
              end
            end

            def read_binary_entry(zip, path)
              instrument('epub.read_binary_entry') do
                data = zip.read(path)
                data.force_encoding(Encoding::BINARY)
              end
            end

            def normalize_text(content)
              Adapters::BookSources::Epub::XmlTextNormalizer.normalize(content)
            end

            def resolve_href(opf_path, href)
              return nil unless href

              base = File.dirname(opf_path)
              root = File.expand_path(File.join('/', base, href), '/')
              root.sub(%r{^/}, '')
            end
          end
        end
      end
    end
  end
end
