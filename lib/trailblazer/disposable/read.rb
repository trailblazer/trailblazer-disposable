module Trailblazer
  module Disposable
    module Schema
      module_function

      module Runtime
        module_function

        def run_binding(definition, source)
          value = read(source, definition)

          value = run_scalar(definition, value)

          ary = [definition[:name].to_sym, value]
        end

        def run_populator(definition, hash)
          definition[:populator].(hash, definition)
        end

        def run_scalar(definition, value)
          value = definition[:activity].(definition, value) # NestedActivity.()

          value = run_populator(definition, value)
        end

        def run_collection(definition, value)
          value.each_with_index.collect do |item, i|
            run_scalar(definition, item) # TODO: add {i}.
          end
        end

        def run_definitions(definition, source)
          definition[:definitions].collect do |dfn|
            run_binding(dfn, source)
          end
        end

        # @private
        def read(source, dfn)
          # puts "@@@@@ READ #{dfn[:name].inspect} from #{source}"
          source[ dfn[:name].to_sym ]
        end
      end


      # binding
      #   read
      #   process        # value.collect (definitions or items).binding.call
      #   "populator"
      #   return [name, value]

      # field
      #   process        #     1st: definitions.collect   ... later: vale.collect, ...
      #   populator
      #   return value

      def process(definition, value, populator:)
        if definition[:nested]

          if definition[:collection]
            # a collection property is a normal property with :nested property (binding) that implements that special
            # iteration without reading (or rather, reading by index)
            value = value.each_with_index.collect do |item, i|
              process( definition.merge!(collection: false), item, populator: populator) # FIXME: we don't need to #read anymore. Also, we need to pass in the nested definition, not the collection.
            end
            populator = definition[:collection_populator] # FIXME: this is, of course, wrong design of the property/nesting.

            # raise value.inspect

          else # nested property
            value = for_definitions(definition[:twin], value, populator: populator)
            puts "!!!!@@@@@ #{definition[:name].inspect} -- #{value.inspect}"
            value = Hash[value]
          end
        end

        # if :collection, make a Twin::Collection here!
        value = populator.(value, definition: definition)
        puts ">>> #{value.inspect} +++++++++ #{populator} for "
        value
      end

      def for_definitions(schema, source, **options)
        schema.definitions.collect do |dfn|
          for_property(dfn, source, **options)
        end
      end

      # @private
      def read(source, dfn)
        # puts "@@@@@ READ #{dfn[:name].inspect} from #{source}"
        source[ dfn[:name].to_sym ]
      end
    end

    module Read
      module_function

      def from_h(source, definitions:, populator:, collection_populator:nil, definition:)

        ary = definitions.collect do |dfn|
          # next if dfn[:readable] == false # FIXME: is that really what we want?

          value = read(source, dfn)
          # value = hash[ dfn[:private_name] ]
          # value ||= dfn[:default] # FIXME: what if we want nil? Also, optional? Do we need it>

          value = Disposable::Processor::Property.(dfn, value) { |_value, i|
            for_nested(
              _value,
              populator:            populator,
              # collection_populator: collection_populator,
              definition:           dfn
            )
          } if dfn[:nested]

          # DISCUSS
          # wrap collections into Twin::Collection.
          # if dfn[:collection]
          #   value = Twin::Collection.for_models(Twin::Twinner.new(Twin::Build, dfn), []) # TODO: make this simpler.
          # end

          [dfn[:name].to_sym, value]
        end.compact

        pp ary

        populator.(Hash[ary], definition: definition)
      end

      # @private
      def read(source, dfn)
        source[ dfn[:name].to_sym ]
      end

      def for_nested(source, populator:, definition:)
        from_h(
          source,
          definitions: definition[:nested].definitions,
          definition:  definition,
          populator:   populator
        )
      end
    end
  end
end
