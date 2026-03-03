# frozen_string_literal: true

module Shoko
  module Adapters
    module Storage
      # Chapter persistence helpers for `JsonCacheStore`.
      class JsonCacheStore
        CHAPTER_ROW_EXCLUDED_KEYS = %w[raw_content lines_json blocks_json].freeze

        private

        def chapters_dir(sha)
          File.join(@cache_root, CHAPTERS_DIRNAME, normalize_sha!(sha))
        end

        def chapter_generation_dir(sha, generation)
          gen = generation.to_s.strip
          raise ArgumentError, 'chapter generation is invalid' unless CHAPTERS_GENERATION_PATTERN.match?(gen)

          File.join(chapters_dir(sha), gen.downcase)
        end

        def chapter_raw_dir(sha, generation)
          File.join(chapter_generation_dir(sha, generation), CHAPTERS_RAW_DIRNAME)
        end

        def chapter_raw_file(sha, generation, position)
          idx = Integer(position)
          raise ArgumentError, 'chapter position must be >= 0' if idx.negative?

          name = format("%0#{CHAPTER_FILENAME_DIGITS}d.xhtml", idx)
          File.join(chapter_raw_dir(sha, generation), name)
        end

        def normalize_chapter_generation(generation)
          gen = generation.to_s.strip.downcase
          CHAPTERS_GENERATION_PATTERN.match?(gen) ? gen : nil
        end

        def normalize_expected_chapter_count(expected_count)
          count = expected_count.to_i
          return nil if count.negative?
          return nil if count > MAX_CHAPTER_COUNT

          count
        end

        def chapter_files_complete?(sha, generation, expected_count)
          raw_dir = chapter_raw_dir(sha, generation)
          return false unless Dir.exist?(raw_dir)

          expected_count.times do |idx|
            return false unless File.file?(chapter_raw_file(sha, generation, idx))
          end
          true
        end

        def persist_chapters(sha, chapter_rows)
          chapter_rows = Array(chapter_rows)
          generation = new_chapter_generation
          return [[], generation, 0] if chapter_rows.empty?

          FileUtils.mkdir_p(chapter_raw_dir(sha, generation))
          rows, total_bytes = persist_chapter_rows(sha, generation, chapter_rows)
          [rows, generation, total_bytes]
        end

        def new_chapter_generation
          SecureRandom.hex(CHAPTERS_GENERATION_BYTES)
        end

        def persist_chapter_rows(sha, generation, chapter_rows)
          rows = []
          total_bytes = 0
          chapter_rows.each do |row|
            filtered, bytesize = persist_chapter_row(sha, generation, row)
            rows << filtered
            total_bytes += bytesize
          end
          [rows, total_bytes]
        end

        def persist_chapter_row(sha, generation, row)
          idx = chapter_row_index(row)
          text = chapter_row_raw_content(row).to_s
          AtomicFileWriter.write(chapter_raw_file(sha, generation, idx), text)
          [filtered_chapter_index_row(row, idx), text.bytesize]
        end

        def chapter_row_index(row)
          raise ArgumentError, 'chapter row must be a Hash' unless row.is_a?(Hash)

          position = row[:position] || row['position']
          idx = Integer(position)
          raise ArgumentError, 'chapter position must be >= 0' if idx.negative?

          idx
        end

        def chapter_row_raw_content(row)
          row[:raw_content] || row['raw_content']
        end

        def filtered_chapter_index_row(row, idx)
          filtered = {}
          row.each do |key, value|
            key_str = key.to_s
            next if CHAPTER_ROW_EXCLUDED_KEYS.include?(key_str)

            filtered[key_str] = value
          end
          filtered['position'] = idx
          filtered
        end

        def cleanup_old_chapter_generations(sha, keep:)
          base = chapters_dir(sha)
          return unless Dir.exist?(base)

          keep_name = keep.to_s.strip.downcase
          Dir.children(base).each do |entry|
            next if entry == keep_name

            path = File.join(base, entry)
            next unless File.directory?(path)
            next unless CHAPTERS_GENERATION_PATTERN.match?(entry)

            FileUtils.rm_rf(path)
          end
        rescue Shoko::Error
          nil
        end

        def cleanup_failed_chapter_generation(sha, generation)
          path = chapter_generation_dir(sha, generation)
          FileUtils.rm_rf(path)
        rescue Shoko::Error
          nil
        end
      end
    end
  end
end
