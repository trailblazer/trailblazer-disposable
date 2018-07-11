module Trailblazer
  module Disposable
    module Schema
      module_function

      # module Processor
      #   module_function

      #   def call(definition, source)
      #     source.each_with_index.collect do |item, i|

      #     end
      #   end
      # end

      def for_property(definition, source, populator:)
        value = read(source, definition)

        # ary = Processor.(definition, value) if definition[:nested] # go through all definitions! if it's a collection, processor over the collection
        #   for_definitions(definition[:nested], value) ..

        _ary = value

        if definition[:nested]
          if definition[:collection]

            _ary = value.each_with_index.collect do |item, i|
              pp item
              for_property( definition[:nested], item, populator: populator) # FIXME: we don't need to #read anymore. Also, we need to pass in the nested definition, not the collection.
            end

            raise _ary.inspect

          else
            _ary = for_definitions(definition[:twin], value, populator: populator) # only for !:collection
            _ary = Hash[_ary]
          end
        end



        # if :collection, make a Twin::Collection here!
        _ary = populator.(_ary, definition: definition)

        ary = [definition[:name].to_sym, _ary]
        # ary = [definition[:name].to_sym, Hash[_ary]]
        pp ary
        ary
      end

      def for_definitions(schema, source, **options)
        schema.definitions.collect do |dfn|
          for_property(dfn, source, **options)
        end
      end

      # @private
      def read(source, dfn)
        puts "@@@@@ READ #{dfn[:name].inspect} from #{source}"
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
