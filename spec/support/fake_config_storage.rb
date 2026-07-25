# frozen_string_literal: true

require 'fileutils'

module SpecSupport
  # A real, complete implementation of the ConfigStorage port backed by a
  # temporary directory.
  #
  # Specs used to hand-roll this as an `Object.new` with a handful of
  # `define_singleton_method` calls — eight copies, each implementing a
  # different subset of the port, so a store that started calling one more port
  # method broke them all with NoMethodError. Implementing the port once, in
  # full, is both less code and a more honest double.
  class FakeConfigStorage
    include Shoko::Application::Ports::Outbound::ConfigStorage

    attr_reader :config_dir

    def initialize(config_dir, filename: 'config.json')
      @config_dir = config_dir
      @filename = filename
    end

    def config_file(filename = @filename)
      File.join(@config_dir, filename)
    end

    def ensure_config_dir
      FileUtils.mkdir_p(@config_dir)
    end

    def atomic_write(path, data)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, data)
    end

    def read_file(path)
      File.exist?(path) ? File.read(path) : nil
    end

    def file_exist?(path)
      File.exist?(path)
    end
  end
end
