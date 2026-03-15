# frozen_string_literal: true

require 'time'
require_relative '../../shared/hash_normalizer'

module Shoko
  module Core
    module Events
      # Base class for all domain events.
      #
      # Domain events represent something that has happened in the domain
      # and are used to trigger side effects and maintain loose coupling
      # between different parts of the system.
      #
      # @example Creating a domain event
      #   class BookmarkAdded < BaseDomainEvent
      #     attribute :book_path, String
      #     attribute :bookmark, Bookmark
      #   end
      #
      # @example Using a domain event
      #   event = BookmarkAdded.new(book_path: '/path/to/book.epub', bookmark: bookmark)
      #   event_bus.publish(event)
      class BaseDomainEvent
        # Event metadata
        attr_reader :event_id, :occurred_at, :aggregate_id, :version

        def initialize(event_id:, occurred_at:, aggregate_id: nil, version: 1, **attributes)
          @event_id = event_id
          @occurred_at = normalize_occurred_at(occurred_at)
          @aggregate_id = aggregate_id
          @version = version
          @attributes = attributes

          validate_metadata!
          validate_required_attributes
          validate_attribute_types
        end

        # Get event type name
        #
        # @return [String] Event type name
        def event_type
          self.class.name.split('::').last
        end

        # Get event data as hash
        #
        # @return [Hash] Event data
        def event_data
          @attributes.dup
        end

        # Get specific attribute value
        #
        # @param name [Symbol] Attribute name
        # @return [Object] Attribute value
        def get_attribute(name)
          @attributes[name]
        end

        # Convert event to hash for serialization
        #
        # @return [Hash] Serialized event
        def to_h
          {
            event_id: @event_id,
            event_type: event_type,
            occurred_at: @occurred_at.iso8601,
            aggregate_id: @aggregate_id,
            version: @version,
            data: @attributes,
          }
        end

        # Create event from hash
        #
        # @param hash [Hash] Serialized event data
        # @return [BaseDomainEvent] Reconstructed event
        def self.from_h(hash)
          event = allocate
          event.restore_from_hash(hash)
          event
        end

        # Define required attributes for the event
        #
        # @example
        #   class MyEvent < BaseDomainEvent
        #     required_attributes :user_id, :action
        #   end
        def self.required_attributes(*attrs)
          @required_attributes ||= []
          @required_attributes.concat(attrs) if attrs.any?
          @required_attributes
        end

        # Define typed attributes for the event
        #
        # @example
        #   class MyEvent < BaseDomainEvent
        #     typed_attributes user_id: String, count: Integer
        #   end
        def self.typed_attributes(types = {})
          @typed_attributes ||= {}
          @typed_attributes.merge!(types) if types.any?
          @typed_attributes
        end

        # Check if event is of specific type
        #
        # @param type [String, Symbol] Event type to check
        # @return [Boolean] True if event is of specified type
        def of_type?(type)
          event_type == type.to_s
        end

        # String representation of the event
        #
        # @return [String] String representation
        def to_s
          "#{event_type}(#{@event_id})[#{@occurred_at}]"
        end

        # Equality comparison
        #
        # @param other [BaseDomainEvent] Other event to compare
        # @return [Boolean] True if events are equal
        def ==(other)
          return false unless other.is_a?(BaseDomainEvent)

          @event_id == other.event_id &&
            event_type == other.event_type &&
            @attributes == other.event_data
        end

        private

        def normalize_occurred_at(value)
          return value.utc if value.is_a?(Time)

          Time.parse(value.to_s).utc
        rescue ArgumentError => e
          raise ArgumentError, "occurred_at must be a valid timestamp: #{e.message}"
        end

        def validate_metadata!
          raise ArgumentError, 'event_id is required' if @event_id.nil? || @event_id.to_s.strip.empty?
          raise ArgumentError, 'occurred_at is required' if @occurred_at.nil?
        end

        public

        def restore_from_hash(hash)
          normalized = Shoko::Shared::HashNormalizer.symbolize_keys(hash) || {}
          @event_id = normalized[:event_id]
          @occurred_at = Time.parse(normalized[:occurred_at].to_s)
          @aggregate_id = normalized[:aggregate_id]
          @version = normalized[:version] || 1
          @attributes = Shoko::Shared::HashNormalizer.deep_symbolize(normalized[:data] || {})
        end

        private

        def validate_required_attributes
          klass = self.class
          required = klass.required_attributes
          return unless required

          missing = required - @attributes.keys
          return if missing.empty?

          raise ArgumentError, "Missing required attributes: #{missing.join(', ')}"
        end

        def validate_attribute_types
          klass = self.class
          typed = klass.typed_attributes
          return unless typed

          typed.each do |attr, type|
            value = @attributes[attr]
            next if value.nil? # Allow nil values

            raise TypeError, "Attribute #{attr} must be of type #{type}, got #{value.class}" unless value.is_a?(type)
          end
        end
      end
    end
  end
end
