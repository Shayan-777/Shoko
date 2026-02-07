# frozen_string_literal: true

require 'pathname'

require_relative '../xml_text_normalizer'

module Shoko
  module Core::BookFormats::Epub
    # Reads OPF and related XML entries from a zip or filesystem path.
    class OPFEntryReader
      def initialize(opf_path, zip: nil)
        @opf_path = opf_path
        @opf_dir = File.dirname(opf_path)
        @zip = zip
      end

      def zip?
        !@zip.nil?
      end

      def read_raw(path)
        zip? ? @zip.read(path) : File.read(path)
      end

      def read_entry(path)
        normalize_xml_text(read_raw(path))
      end

      def safe_read_entry(path)
        read_entry(path)
      rescue StandardError
        nil
      end

      def entry_exists?(path)
        zip? ? !!@zip.find_entry(path) : File.exist?(path)
      end

      def join_path(href)
        expand_path(@opf_dir, href)
      end

      def expand_path(base_dir, href)
        return nil if href.nil? || href.to_s.empty?

        if zip?
          File.expand_path(File.join('/', base_dir, href), '/').sub(%r{^/}, '')
        else
          File.expand_path(File.join(base_dir, href))
        end
      end

      def normalize_opf_relative_href(href)
        return nil if href.nil? || href.to_s.empty?

        joined = join_path(href)
        return nil unless joined

        Pathname.new(joined).relative_path_from(Pathname.new(@opf_dir)).to_s
      rescue ArgumentError
        href.to_s
      end

      def opf_relative_path(path)
        return nil if path.nil? || path.to_s.empty?

        Pathname.new(path).relative_path_from(Pathname.new(@opf_dir)).to_s
      rescue ArgumentError
        nil
      end

      def normalize_xml_text(content)
        XmlTextNormalizer.normalize(content)
      end
    end
  end
end
