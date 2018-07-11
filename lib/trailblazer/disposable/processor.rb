module Trailblazer
  # This is similar to Representable::Serializer and allows to apply a piece of logic (the
  # block passed to #call) to every twin for this property.
  #
  # For a scalar property, this will be run once and yield the property's value.
  # For a collection, this is run per item and yields the item.
  #:private:
  module Disposable::Processor
    module Property
      module_function

      def call(definition, value, &block)
        if definition[:collection]
          apply_for_collection(value, &block)
        else
          apply_for_property(value, &block)
        end
      end

      def apply_for_collection(value)
        (value || []).each_with_index.collect { |nested_twin, i| yield(nested_twin, i) } # returns Array instance.
      end

      def apply_for_property(value)
        twin = value or return nil
        yield(twin)
      end
    end
  end

end
