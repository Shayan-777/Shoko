# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative '../storage/config_paths'
require_relative '../../shared/errors'

module Shoko
  module Adapters
    module Translation
      # Storage policy for installed translation language packs.
      #
      # Layout: <config>/translator/models/<from>-<to>/ holding the model
      # binary, the SentencePiece vocabulary and a small pack.json manifest
      # written at install time.
      class ModelStore
        MANIFEST_NAME = 'pack.json'

        InstalledPack = Data.define(:from, :to, :dir, :model_path, :vocab_path, :version)

        def initialize(root: nil, logger: nil)
          @root = root || Storage::ConfigPaths.config_path('translator', 'models')
          @logger = logger
        end

        attr_reader :root

        def installed_packs
          return [] unless Dir.exist?(@root)

          Dir.children(@root).sort.filter_map do |entry|
            read_pack(File.join(@root, entry))
          end
        end

        def installed?(from, to)
          !find(from, to).nil?
        end

        def find(from, to)
          read_pack(pack_dir(from, to))
        end

        def pack_dir(from, to)
          File.join(@root, "#{sanitize(from)}-#{sanitize(to)}")
        end

        def create_pack_dir(from, to)
          dir = pack_dir(from, to)
          FileUtils.mkdir_p(dir)
          dir
        end

        def write_manifest(from, to, version:, model_file:, vocab_file:)
          dir = create_pack_dir(from, to)
          manifest = {
            from: from.to_s,
            to: to.to_s,
            version: version.to_s,
            model: File.basename(model_file.to_s),
            vocab: File.basename(vocab_file.to_s),
          }
          File.write(File.join(dir, MANIFEST_NAME), JSON.pretty_generate(manifest))
          manifest
        end

        def remove(from, to)
          dir = pack_dir(from, to)
          FileUtils.rm_rf(dir) if File.directory?(dir)
          nil
        end

        private

        def sanitize(code)
          code.to_s.gsub(/[^A-Za-z-]/, '')
        end

        def read_pack(dir)
          manifest_path = File.join(dir, MANIFEST_NAME)
          return nil unless File.file?(manifest_path)

          build_pack(dir, JSON.parse(File.read(manifest_path)))
        # resilient-boundary
        rescue StandardError => e
          swallow_manifest_error(dir, e)
        end

        def build_pack(dir, manifest)
          model_path = File.join(dir, File.basename(manifest.fetch('model', '')))
          vocab_path = File.join(dir, File.basename(manifest.fetch('vocab', '')))
          return nil unless File.file?(model_path) && File.file?(vocab_path)

          InstalledPack.new(
            from: manifest.fetch('from', ''),
            to: manifest.fetch('to', ''),
            dir: dir,
            model_path: model_path,
            vocab_path: vocab_path,
            version: manifest.fetch('version', '')
          )
        end

        # A corrupt pack directory must not take the translator down; the
        # pack simply does not appear as installed.
        def swallow_manifest_error(dir, error)
          @logger&.error('translator.pack_manifest_unreadable',
                         dir: dir, error: error.class.name, message: error.message)
          nil
        end
      end
    end
  end
end
