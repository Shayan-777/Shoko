# frozen_string_literal: true

module Shoko
  module Adapters
    module Rss
      # Full-article hydration helpers for the RSS reader service.
      module RssReaderServiceContentSupport
        private

        def hydrate_article_payloads(parsed_articles)
          Array(parsed_articles).map { |payload| hydrate_article_payload(payload) }
        end

        def hydrate_article_payload(payload)
          article = payload.dup
          return article unless should_fetch_full_content?(article)

          full_content = @article_content_fetcher.fetch(article[:url])
          return article unless full_content_more_complete?(article, full_content)

          article.merge(
            content: full_content,
            summary: derive_summary(article[:summary], full_content)
          )
        rescue ArticleContentFetcher::FetchError => e
          log_debug('rss_reader.article_content_fetch_failed', url: article[:url], error: e.message)
          article
        end

        def should_fetch_full_content?(payload)
          return false unless @article_content_fetcher

          url = payload[:url].to_s.strip
          return false if url.empty?

          content = payload[:content].to_s.strip
          summary = payload[:summary].to_s.strip
          content.empty? || truncated_content?(content, summary)
        end

        def truncated_content?(content, summary)
          content.length < self.class::FULL_CONTENT_MIN_LENGTH &&
            content.length <= summary.length + self.class::FULL_CONTENT_GAIN_THRESHOLD
        end

        def full_content_more_complete?(payload, full_content)
          current = payload[:content].to_s.strip
          fetched = full_content.to_s.strip
          return false if fetched.empty?

          current.empty? || fetched.length > current.length + self.class::FULL_CONTENT_GAIN_THRESHOLD
        end

        def derive_summary(current_summary, full_content)
          summary = current_summary.to_s.strip
          return summary unless summary.empty?

          excerpt_from(full_content)
        end
      end
    end
  end
end
