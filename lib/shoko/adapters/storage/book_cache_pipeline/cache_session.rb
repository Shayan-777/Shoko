# frozen_string_literal: true

require_relative '../../support/lifecycle_helpers'
require_relative '../../support/progress_range_reporter'

module Shoko
  module Adapters
    module Storage
      class BookCachePipeline
        # Handles cache loading/rebuilding for a specific cache instance.
        class CacheSession
          include Shoko::Adapters::Support::LifecycleHelpers

          PROGRESS_REPORTER_KEYWORD_KINDS = %i[key keyreq keyrest].freeze

          def initialize(cache:, formatting_service:, importer_class:, load_callback:, progress_reporter: nil,
                         runtime_config: nil, logger: nil, image_cache_warmup: nil)
            @cache = cache
            @formatting_service = formatting_service
            @importer_class = importer_class
            @load_callback = load_callback
            @progress_reporter = progress_reporter
            @runtime_config = runtime_config
            @logger = logger
            @image_cache_warmup = image_cache_warmup
          end

          def load
            cache_file = @cache.cache_file?
            report('Loading cached book...') if cache_file
            result = result_from_initial_payload
            return result if result

            raise Shoko::CacheLoadError.new(@cache.cache_path, 'cached payload unavailable') if cache_file

            import_and_result
          end

          def fast_load
            report('Loading cached book...')
            payload, cache_status = payload_from_cache
            context = PayloadContext.new(payload: payload, cache_status: cache_status)
            result_from_payload_or_nil(context)
          end

          private

          def initial_payload
            return @cache.read_cache(strict: true) if @cache.cache_file?

            payload_from_source
          end

          def payload_from_cache
            payload = @cache.read_cache(strict: true)
            raise Shoko::CacheLoadError.new(@cache.cache_path, 'cached payload unavailable') unless payload

            cache_status = CacheStatus.hit(payload)
            [payload, cache_status]
          end

          def payload_from_source
            @cache.load_for_source(strict: true)
          end

          def result_from_initial_payload
            payload = initial_payload
            payload && result_from_payload(
              PayloadContext.new(payload: payload, cache_status: CacheStatus.hit(payload))
            )
          end

          def result_from_payload(context)
            payload = rebuild_if_incomplete(context)
            result_for(payload, loaded_from_cache: context.cache_status.loaded_from_cache?)
          end

          def result_from_payload_or_nil(context)
            context.payload && begin
              payload = rebuild_if_incomplete(context)
              payload && result_for(payload, loaded_from_cache: context.cache_status.loaded_from_cache?)
            end
          end

          def rebuild_if_incomplete(context)
            payload = context.payload
            return payload unless context.cache_status.loaded_from_cache?

            checker = CacheIntegrityChecker.new(cache: @cache, payload: payload)
            return payload unless checker.incomplete?

            raise Shoko::CacheLoadError.new(@cache.cache_path, 'cached payload is incomplete')
          end

          def result_for(payload, loaded_from_cache:)
            book = payload.book
            cache_path = @cache.cache_path
            source_path = payload.source_path || @cache.source_path
            Result.new(
              book: book,
              cache_path: cache_path,
              source_path: source_path,
              loaded_from_cache: loaded_from_cache,
              payload: payload
            )
          end

          def import_and_result
            context = PayloadContext.new(payload: rebuild_cache, cache_status: CacheStatus.miss)
            result_from_payload(context)
          end

          def rebuild_cache
            resolved_class = resolve_importer_class
            importer = resolved_class.new(**importer_init_kwargs(resolved_class))
            book_data = importer.import(@cache.source_path)
            report('Creating JSON cache...', progress: 0.0)
            cache_write_ok = @cache.write_book!(book_data)
            raise Shoko::CacheLoadError.new(@cache.cache_path, 'cache write failed') unless cache_write_ok
            warm_image_cache(book_data)

            report('Finalizing cache...', progress: 1.0)
            payload = payload_from_source
            return payload if payload

            raise Shoko::CacheLoadError.new(@cache.cache_path, 'cache payload unavailable after write')
          end

          def resolve_importer_class
            source = @cache.source_path.to_s
            from_registry = Shoko::Adapters::BookSources::FormatRegistry.importer_for(source)
            from_registry || @importer_class
          end

          def importer_init_kwargs(importer_class)
            kwargs = {
              formatting_service: @formatting_service,
              progress_reporter: @progress_reporter,
            }
            return kwargs unless importer_supports_keyword?(importer_class, :runtime_config)

            kwargs[:runtime_config] = @runtime_config
            kwargs
          end

          def importer_supports_keyword?(importer_class, keyword)
            parameters = importer_class.instance_method(:initialize).parameters
            parameters.any? { |kind, name| KEYWORD_PARAMETER_KINDS.include?(kind) && name == keyword }
          end

          def warm_image_cache(book_data)
            return unless @image_cache_warmup

            report('Caching inline images...', progress: 0.92)
            @image_cache_warmup.warm_book_data(**image_cache_warmup_kwargs(book_data))
          rescue Shoko::Error => e
            @logger&.debug(
              'book_cache_pipeline.image_cache_warmup_failed',
              error: e.class.name,
              message: e.message,
              path: @cache.source_path
            )
          end

          def image_cache_warmup_kwargs(book_data)
            kwargs = {
              book_data: book_data,
              book_sha: @cache.sha256,
              epub_path: @cache.source_path,
            }
            reporter = image_cache_progress_reporter
            kwargs[:progress_reporter] = reporter if reporter && image_cache_warmup_supports_progress_reporter?
            kwargs
          end

          def image_cache_progress_reporter
            return nil unless @progress_reporter

            Shoko::Adapters::Support::ProgressRangeReporter.new(
              reporter: @progress_reporter,
              start_progress: 0.92,
              end_progress: 0.99
            )
          end

          def image_cache_warmup_supports_progress_reporter?
            parameters = @image_cache_warmup.method(:warm_book_data).parameters
            parameters.any? do |kind, name|
              PROGRESS_REPORTER_KEYWORD_KINDS.include?(kind) && name == :progress_reporter
            end ||
              parameters.any? { |kind, _name| kind == :keyrest }
          end
        end

        private_constant :CacheSession
      end
    end
  end
end
