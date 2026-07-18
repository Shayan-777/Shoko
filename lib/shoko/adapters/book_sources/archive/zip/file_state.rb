# frozen_string_literal: true

require_relative 'file'

module Shoko
  module Zip
    # Encapsulates ZIP file state
    class FileState
      attr_reader :io, :entries, :limits

      def initialize(path, limits)
        @io = ::File.open(path, 'rb', &:dup)
        @entries = {}
        @limits = limits
        @closed = false
      end

      def close
        return if @closed

        @io&.close
        @closed = true
      end

      def closed?
        @closed || !@io || @io.closed?
      end
    end
  end
end
