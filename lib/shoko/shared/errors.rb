# frozen_string_literal: true

module Shoko
  # Base error class for Shoko
  class Error < StandardError; end

  # Raised when EPUB file cannot be parsed
  class EPUBParseError < Error
    attr_reader :file_path

    def initialize(message, file_path)
      super("Failed to parse EPUB at #{file_path}: #{message}")
      @file_path = file_path
    end
  end

  # Raised when required file is not found
  class FileNotFoundError < Error
    attr_reader :file_path

    def initialize(file_path)
      super("File not found: #{file_path}")
      @file_path = file_path
    end
  end

  # Raised when configuration is invalid
  class ConfigurationError < Error; end

  # Raised when no interactive terminal is available
  class TerminalUnavailableError < Error
    def initialize
      super('Interactive terminal not available')
    end
  end

  # Raised when reader state is invalid
  class InvalidStateError < Error
    attr_reader :state

    def initialize(message, state)
      super("Invalid reader state: #{message}")
      @state = state
    end
  end

  # Raised when navigation is not possible
  class NavigationError < Error
    attr_reader :direction, :reason

    def initialize(direction, reason)
      super("Cannot navigate #{direction}: #{reason}")
      @direction = direction
      @reason = reason
    end
  end

  # Raised when bookmark operation fails
  class BookmarkError < Error
    attr_reader :operation

    def initialize(operation, message)
      super("Bookmark #{operation} failed: #{message}")
      @operation = operation
    end
  end

  # Raised when rendering fails
  class RenderError < Error
    attr_reader :component

    def initialize(component, message)
      super("Rendering failed in #{component}: #{message}")
      @component = component
    end
  end

  # Raised when content normalization produces no semantic blocks
  class FormattingError < Error
    attr_reader :source

    def initialize(source, message)
      super("Formatting failed for #{source}: #{message}")
      @source = source
    end
  end

  # Raised when cached book data cannot be loaded or is incompatible.
  class CacheLoadError < Error
    attr_reader :path

    def initialize(path, message = 'Cache is corrupt or incompatible')
      super("Cache load failed for #{path}: #{message}")
      @path = path
    end
  end

  # Raised when storage operations fail (file I/O, JSON parsing, etc.)
  class StorageError < Error
    attr_reader :operation, :path

    def initialize(operation, path = nil, message = nil)
      msg = "Storage #{operation} failed"
      msg += " for #{path}" if path
      msg += ": #{message}" if message
      super(msg)
      @operation = operation
      @path = path
    end
  end

  # Raised when state updates fail
  class StateUpdateError < Error
    attr_reader :path

    def initialize(path, message = nil)
      msg = "State update failed for path #{path.inspect}"
      msg += ": #{message}" if message
      super(msg)
      @path = path
    end
  end

  # Raised when pagination operations fail
  class PaginationError < Error
    attr_reader :operation

    def initialize(operation, message = nil)
      msg = "Pagination #{operation} failed"
      msg += ": #{message}" if message
      super(msg)
      @operation = operation
    end
  end

  # Raised when annotation operations fail
  class AnnotationError < Error
    attr_reader :operation

    def initialize(operation, message = nil)
      msg = "Annotation #{operation} failed"
      msg += ": #{message}" if message
      super(msg)
      @operation = operation
    end
  end
end
