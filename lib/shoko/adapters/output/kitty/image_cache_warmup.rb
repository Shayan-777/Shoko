# frozen_string_literal: true

require 'shoko/shared/hash_normalizer'
require 'shoko/application/ports/outbound/book_resource_warmup'

module Shoko
  module Adapters
    module Output
      module Kitty
        # Pre-populates persistent PNG cache entries for renderable EPUB images.
        class ImageCacheWarmup
          include Shoko::Application::Ports::Outbound::BookResourceWarmup

          Result = Struct.new(:status, :warmed, :cached)
          IMG_SRC_PATTERN = /<img\b[^>]*\bsrc\s*=\s*(["'])(.*?)\1/im

          def initialize(kitty_image_renderer:, logger: nil)
            @kitty_image_renderer = kitty_image_renderer
            @logger = logger
          end

          def warm_document(document, progress_reporter: nil)
            return skipped_result unless warmable_path?(document&.canonical_path)

            warm_chapters(
              chapters: Array(document&.chapters),
              book_sha: document&.cache_sha,
              epub_path: document&.canonical_path,
              progress_reporter: progress_reporter
            )
          rescue Shoko::Error => e
            log_failure('kitty.image_cache_warmup.document_failed', epub_path: document&.canonical_path, error: e)
            error_result
          end

          def warm_book_data(book_data:, book_sha:, epub_path:, progress_reporter: nil)
            return skipped_result unless warmable_path?(epub_path)

            warm_chapters(
              chapters: Array(book_data&.chapters),
              book_sha: book_sha,
              epub_path: epub_path,
              progress_reporter: progress_reporter
            )
          rescue Shoko::Error => e
            log_failure('kitty.image_cache_warmup.book_data_failed', epub_path: epub_path, error: e)
            error_result
          end

          private

          def warm_chapters(chapters:, book_sha:, epub_path:, progress_reporter:)
            jobs = image_jobs_for(chapters)
            return skipped_result if jobs.empty?

            warmed = 0
            cached = 0

            jobs.each_with_index do |job, index|
              progress_reporter&.update_status(
                message: image_cache_message(index + 1, jobs.length),
                progress: image_cache_progress(index, jobs.length)
              )
              status = warm_image_job(job, book_sha: book_sha, epub_path: epub_path)
              warmed += 1 if status == :warmed
              cached += 1 if status == :cached
            end

            progress_reporter&.update_status(message: 'Caching inline images...', progress: 1.0)
            Result.new(result_status(warmed: warmed, cached: cached), warmed, cached)
          end

          def chapter_entry_path_for(chapter)
            metadata = Shoko::Shared::HashNormalizer.symbolize_keys(chapter&.metadata)
            return nil unless metadata.is_a?(Hash)

            metadata[:source_path] || metadata[:href]
          end

          def image_sources_for(chapter)
            raw = chapter&.raw_content.to_s
            return [] if raw.empty?

            raw.scan(IMG_SRC_PATTERN).map { |(_, src)| src.to_s.strip }.reject(&:empty?).uniq
          end

          def warmable_path?(path)
            expanded = File.expand_path(path.to_s)
            File.file?(expanded) && File.extname(expanded).casecmp('.epub').zero?
          end

          def skipped_result
            Result.new(:skipped, 0, 0)
          end

          def error_result
            Result.new(:error, 0, 0)
          end

          def log_failure(event, epub_path:, error:)
            @logger&.debug(event, error: error.class.name, message: error.message, path: epub_path.to_s)
          end

          def image_jobs_for(chapters)
            Array(chapters).flat_map do |chapter|
              chapter_entry_path = chapter_entry_path_for(chapter)
              next [] if chapter_entry_path.nil?

              image_sources_for(chapter).filter_map do |src|
                next unless @kitty_image_renderer.renderable_source?(src)

                { chapter_entry_path: chapter_entry_path, src: src }
              end
            end
          end

          def result_status(warmed:, cached:)
            return :warmed if warmed.positive?
            return :cached if cached.positive?

            :skipped
          end

          def warm_image_job(job, book_sha:, epub_path:)
            @kitty_image_renderer.warm_cache(
              book_sha: book_sha,
              epub_path: epub_path,
              chapter_entry_path: job.fetch(:chapter_entry_path),
              src: job.fetch(:src)
            )
          end

          def image_cache_message(done, total)
            "Caching inline images (#{done}/#{total})..."
          end

          def image_cache_progress(index, total)
            return 1.0 if total.to_i <= 0

            index.to_f / total
          end
        end
      end
    end
  end
end
