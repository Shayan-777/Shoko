# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require_relative '../base_adapter'
require_relative '../../shared/errors'
require_relative '../../core/services/version_order'

module Shoko
  module Adapters
    module Translation
      # Fetches the Firefox Translations model catalog from Mozilla Remote
      # Settings and downloads language packs (model + vocabulary) with
      # sha256 verification into the model store.
      #
      # Catalog policy: for every language pair the newest release whose
      # files the engine supports (one shared SentencePiece vocabulary) is
      # offered; alpha versions lose to releases. Pairs published only with
      # split source/target vocabularies are not offered.
      class ModelCatalogService < Shoko::Adapters::BaseAdapter
        RECORDS_URL =
          'https://firefox.settings.services.mozilla.com/v1/buckets/main/collections/translations-models/records'
        ATTACHMENT_BASE_URL = 'https://firefox-settings-attachments.cdn.mozilla.net/'
        MAX_CATALOG_BODY_BYTES = 16 * 1024 * 1024
        # Absolute per-file ceiling. The catalog-declared size is enforced
        # during the stream, but it is remote input too — a compromised
        # catalog declaring an absurd size must not raise the limit, so the
        # effective cap is min(declared, absolute).
        MAX_FILE_BYTES = 512 * 1024 * 1024

        class CatalogError < Shoko::Error; end

        RemoteFile = Data.define(:name, :url, :size, :sha256)
        RemotePack = Data.define(:from, :to, :version, :model, :vocab) do
          def total_size
            model.size + vocab.size
          end
        end

        def initialize(records_url: RECORDS_URL, attachment_base_url: ATTACHMENT_BASE_URL, logger: nil)
          super(logger: logger)
          @records_url = records_url
          @attachment_base_url = attachment_base_url
        end

        # Returns [RemotePack], sorted by language pair.
        def list_remote
          records = fetch_records
          build_packs(records).sort_by { |pack| [pack.from, pack.to] }
        end

        # Downloads a pack's files into the store and writes the manifest.
        # Yields (received_bytes, total_bytes) across both files.
        def download(pack, model_store, &)
          model_store.install(
            pack.from, pack.to,
            version: pack.version,
            model_file: pack.model.name,
            vocab_file: pack.vocab.name
          ) do |dir|
            download_pack_files(pack, dir, &)
          end
        end

        private

        def download_pack_files(pack, dir)
          total = pack.total_size
          received = 0
          [pack.model, pack.vocab].each do |file|
            dest = File.join(dir, File.basename(file.name))
            base = received
            download_file(file, dest) { |done| yield(base + done, total) if block_given? }
            received += file.size
          end
        end

        # --- catalog ----------------------------------------------------------

        def fetch_records
          body = http_get_body(@records_url)
          parsed = JSON.parse(body, symbolize_names: true)
          data = parsed[:data]
          raise CatalogError, 'Malformed catalog response' unless data.is_a?(Array)

          data
        rescue JSON::ParserError => e
          raise CatalogError, "Malformed catalog response: #{e.message}"
        end

        def build_packs(records)
          by_pair = records.group_by { |r| [r[:fromLang].to_s, r[:toLang].to_s] }
          by_pair.filter_map do |(from, to), pair_records|
            next if from.empty? || to.empty?

            best_supported_release(from, to, pair_records)
          end
        end

        def best_supported_release(from, to, records)
          by_version = records.group_by { |r| r[:version].to_s }
          candidates = by_version.filter_map do |version, files|
            model = attachment_record(files, 'model')
            vocab = attachment_record(files, 'vocab')
            next unless model && vocab

            [version, model, vocab]
          end
          version, model, vocab = candidates.max do |left, right|
            Shoko::Core::Services::VersionOrder.compare(left[0], right[0])
          end
          return nil unless version

          RemotePack.new(
            from: from, to: to, version: version,
            model: remote_file(model), vocab: remote_file(vocab)
          )
        end

        def attachment_record(files, file_type)
          files.find { |r| r[:fileType].to_s == file_type && r.dig(:attachment, :location) }
        end

        def remote_file(record)
          attachment = record[:attachment]
          RemoteFile.new(
            name: record[:name].to_s,
            url: attachment_url(attachment[:location]),
            size: attachment[:size].to_i,
            sha256: attachment[:hash].to_s
          )
        end

        def attachment_url(location)
          base = parse_http_uri(@attachment_base_url)
          resolved = parse_http_uri(URI.join(base.to_s, location.to_s).to_s)
          same_origin = resolved.scheme == base.scheme &&
                        resolved.host == base.host &&
                        resolved.port == base.port
          raise CatalogError, 'Catalog attachment points outside the configured CDN' unless same_origin

          resolved.to_s
        rescue URI::InvalidURIError => e
          raise CatalogError, "Invalid attachment URL: #{e.message}"
        end

        # --- downloads --------------------------------------------------------

        def download_file(file, dest_path, &)
          validate_remote_file!(file)
          part_path = "#{dest_path}.part"
          digest = Digest::SHA256.new
          received = stream_to_file(file.url, part_path, digest, max_bytes: max_bytes_for(file), &)
          if received != file.size
            raise CatalogError, "Download size mismatch for #{file.name}: expected #{file.size}, got #{received}"
          end
          raise CatalogError, "Checksum mismatch for #{file.name}" unless digest.hexdigest.casecmp?(file.sha256)

          File.rename(part_path, dest_path)
        ensure
          FileUtils.rm_f(part_path) if part_path
        end

        # The catalog-declared byte count is enforced during the stream, not
        # just implied by the post-download checksum: a lying CDN must not be
        # able to fill the disk before the sha256 check would ever run. The
        # declaration itself is clamped by the absolute ceiling — the catalog
        # is remote input and cannot grant itself a bigger budget.
        def max_bytes_for(file)
          file.size.positive? ? [file.size, MAX_FILE_BYTES].min : MAX_FILE_BYTES
        end

        def validate_remote_file!(file)
          name = file.name.to_s
          unless !name.empty? && File.basename(name) == name && !%w[. ..].include?(name)
            raise CatalogError, 'Catalog contains an invalid attachment name'
          end
          unless file.size.to_i.positive? && file.size.to_i <= MAX_FILE_BYTES
            raise CatalogError, "Catalog contains an invalid size for #{name}"
          end
          return if file.sha256.to_s.match?(/\A[0-9a-fA-F]{64}\z/)

          raise CatalogError, "Catalog contains an invalid checksum for #{name}"
        end

        def stream_to_file(url, part_path, digest, max_bytes:, redirects_left: 2, &)
          uri = parse_http_uri(url)
          received = nil
          with_http(uri) do |http|
            http.request(Net::HTTP::Get.new(uri)) do |response|
              if response.is_a?(Net::HTTPRedirection) && redirects_left.positive?
                redirect = redirect_uri(uri, response['location'])
                received = stream_to_file(redirect.to_s, part_path, digest, max_bytes: max_bytes,
                                                                            redirects_left: redirects_left - 1, &)
                next
              end
              raise CatalogError, "Download failed (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

              received = write_body(response, part_path, digest, max_bytes: max_bytes, &)
            end
          end
          received
        end

        def write_body(response, part_path, digest, max_bytes:)
          received = 0
          File.open(part_path, 'wb') do |io|
            response.read_body do |chunk|
              next_received = received + chunk.bytesize
              raise CatalogError, "Download exceeded declared size (#{max_bytes} bytes)" if next_received > max_bytes

              received = next_received
              io.write(chunk)
              digest.update(chunk)
              yield(received) if block_given?
            end
          end
          received
        end

        def redirect_uri(origin, location)
          raise CatalogError, 'Download redirect has no location' if location.to_s.empty?

          redirect = parse_http_uri(URI.join(origin.to_s, location.to_s).to_s)
          if origin.scheme == 'https' && redirect.scheme != 'https'
            raise CatalogError, 'Download redirect attempted to downgrade HTTPS'
          end

          redirect
        rescue URI::InvalidURIError => e
          raise CatalogError, "Invalid redirect URL: #{e.message}"
        end

        def http_get_body(url)
          uri = parse_http_uri(url)
          response = with_http(uri) do |http|
            http.request(Net::HTTP::Get.new(uri.request_uri)) do |partial|
              partial.body = read_bounded_catalog_body(partial) if partial.is_a?(Net::HTTPSuccess)
            end
          end
          raise CatalogError, "Catalog request failed (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

          response.body
        rescue IOError, SystemCallError, SocketError, Timeout::Error => e
          raise CatalogError, "Catalog request failed: #{e.message}"
        end

        def read_bounded_catalog_body(response)
          buffer = +''
          response.read_body do |chunk|
            if buffer.bytesize + chunk.bytesize > MAX_CATALOG_BODY_BYTES
              raise CatalogError, "Catalog response exceeded #{MAX_CATALOG_BODY_BYTES} bytes"
            end

            buffer << chunk
          end
          buffer
        end

        def parse_http_uri(url)
          ensure_http_dependencies!
          uri = URI.parse(url.to_s)
          raise CatalogError, "Invalid URL: #{url}" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

          uri
        rescue URI::InvalidURIError => e
          raise CatalogError, "Invalid URL: #{e.message}"
        end

        def with_http(uri, &)
          ensure_http_dependencies!
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == 'https'
          http.open_timeout = 5
          http.read_timeout = 30
          http.start(&)
        rescue IOError, SystemCallError, SocketError, Timeout::Error => e
          raise CatalogError, "Download failed: #{e.message}"
        end

        def ensure_http_dependencies!
          return if defined?(Net::HTTP) && defined?(URI::DEFAULT_PARSER)

          require 'net/http'
          require 'uri'
        end
      end
    end
  end
end
