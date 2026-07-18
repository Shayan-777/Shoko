# frozen_string_literal: true

require 'shoko/shared/errors'
require_relative '../../ports/outbound/cache_availability'
require_relative '../../ports/internal/document_loader'
require_relative '../../ports/outbound/prepagination_progress_writer'

module Shoko
  module Application
    module Workflows
      module Menu
        # The pre-pagination batch itself: rebuild the page map of every
        # already-cached library book for one terminal size, reporting
        # progress through the writer port.
        #
        # This runs inside a dedicated low-priority child process (see
        # LibraryPrepaginationWarmup), so it paginates flat out — no
        # cooperative sleeps, no thread politeness — and the menu stays
        # smooth because the OS scheduler, not the GIL, shares the CPU.
        # Every book is still individually defensive: one corrupt book must
        # never abort the rest of the batch.
        class LibraryPrepaginationBatch
          Dependencies = Data.define(
            :catalog_service, :cache_availability, :document_loader,
            :page_calculator, :app_config_store, :progress_writer, :logger
          )

          def initialize(deps:)
            validate_ports!(deps)
            @catalog_service = deps.catalog_service
            @cache_availability = deps.cache_availability
            @document_loader = deps.document_loader
            @page_calculator = deps.page_calculator
            @app_config_store = deps.app_config_store
            @progress_writer = deps.progress_writer
            @logger = deps.logger
          end

          # @return [Symbol] :completed (also when there was genuinely nothing
          #   to do), or :failed when the library could not even be enumerated
          #   — that batch did no work, so it must not count as done or the
          #   warmup would persist the size signature and never retry at this
          #   size. Per-book pagination failures do NOT fail the batch: one
          #   corrupt book must never abort the rest, and its only cost is a
          #   recalculation when it is opened.
          def run(width:, height:)
            paths = candidate_paths
            return :failed if paths.nil?

            process_books(paths, width, height) if paths.any?
            :completed
          ensure
            @progress_writer.finish
          end

          private

          def process_books(paths, width, height)
            @progress_writer.start(total: paths.length, paths: paths)
            paths.each_with_index do |path, index|
              paginate_book(path, width, height)
              @progress_writer.report(done: index + 1)
            end
          end

          # @return [Array<String>, nil] nil when discovery itself failed —
          #   distinct from an empty library, which is a successful no-op.
          def candidate_paths
            entries = Array(@catalog_service.cached_library_entries)
            paths = entries.filter_map { |entry| book_path_from(entry) }.uniq
            paths.select { |path| cached?(path) }
          rescue Shoko::Error => e
            log('candidate_paths_failed', e)
            nil
          end

          def book_path_from(entry)
            return nil unless entry.is_a?(Hash)

            entry[:book_path] || entry[:epub_path]
          end

          def cached?(path)
            @cache_availability.cache_available?(path) == true
          end

          # Build (and persist) the page map for one cached book at the given
          # size. The page calculator skips the heavy work when the layout is
          # already cached, so re-running an unchanged book is cheap.
          def paginate_book(path, width, height)
            document = @document_loader.load(path: path)
            return unless document&.cached?

            config = @app_config_store.load
            @page_calculator.reset_session!
            if config.page_numbering_mode == :absolute
              @page_calculator.build_absolute_map!(width, height, document, config_reader: config)
            else
              @page_calculator.build_dynamic_map!(width, height, document, config_reader: config)
            end
          rescue Shoko::Error => e
            log('paginate_book_failed', e, path: path)
          end

          def log(event, error, **data)
            @logger&.debug("library_prepagination_batch.#{event}",
                           error: error.class.name, message: error.message, **data)
          end

          def validate_ports!(deps)
            contract!(deps.cache_availability, Ports::Outbound::CacheAvailability, 'cache_availability')
            contract!(deps.document_loader, Ports::Internal::DocumentLoader, 'document_loader')
            contract!(deps.progress_writer, Ports::Outbound::PrepaginationProgressWriter, 'progress_writer')
          end

          def contract!(object, port, name)
            return if object.is_a?(port)

            raise ArgumentError, "#{name} must implement #{port.name}"
          end
        end
      end
    end
  end
end
