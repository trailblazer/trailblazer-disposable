# * instead of if dfn[:nested], the dfn already contains its recursor configured,
#   which is called by the parent node processor.
# * the schema is completely "behaviorless". that allows reusing it for different jobs.

module Trailblazer
  module Disposable
    module Schema
      module_function

      module Runtime # aka Hydration
        module_function

        def recurse_nested(dfn, value, *args)
          run_definitions(dfn, value, *args)
        end

        def recurse_scalar(dfn, value, *args)
          value
        end

        def recurse_collection(dfn, value, *args)
          run_collection(dfn[:item_dfn], value, *args)
        end

        def run_binding(dfn, source, **args) # this is an Activity in the end.
          value, stop = read(source, dfn, **args) # TODO: use Railway. # TODO: allow to always run populator.

          return args[:twin] if stop

          value = run_scalar(dfn, value, **args)

          twin = write(value, dfn, **args)
        end


        def run_populator(definition, hash, *args)
          definition[:populator].(hash, definition, *args)
        end

        # step Nested(NestedActivity)
        # step :populator
        #
        # executed per property, every property!
        def run_scalar(definition, value, *args)
          # e.g. recurse_collection
          value = send(definition[:recursion], definition, value, *args) # NestedActivity.()

          value = run_populator(definition, value, *args)
        end

        def run_collection(definition, value, **args)
          value.each_with_index.collect do |item, i|
            run_scalar(definition, item, args.merge(index: i)) # TODO: optimize {i}. TEST!!!!!!!!!
          end
        end

        def run_definitions(definition, source, **args) # fixme: ARRAY SPLAT IS SLOW
          definition[:definitions].collect do |dfn|
            run_binding(dfn, source, **args)
          end
        end

        def read(source, dfn, *)
          return source[ dfn[:name].to_sym ], nil # TODO: sort out the STOP with Railway
        end

        def write(value, dfn, *)
          [dfn[:name].to_sym, value]
        end
      end

      # Reading from document, writing to twin.
      module Parse
        # read
        # populate / coerce
        #   run nested
        # write to twin
        extend Runtime

        class << self
          public :run_definitions # FUCK Ruby

          def run_scalar(dfn, value, **args)
            # in Reform, the parsing pipeline works OK for most people:
            # 1. fetch the property fragment (in {binding})
            # 2. run the populator
            # 3. parse the nested properties "onto" the twin that the populator returned
            # 4. attach the "new" twin to the parent twin.

            populated_cfg = run_populator(dfn, value, **args)

            value = send(dfn[:recursion], dfn, value, populated_cfg) # NestedActivity.()   # FIXME!!!!!!!!!!!!!!! redundant
            # pp value

            populated_cfg[:twin] # DISCUSS: what to return here?
          end

          def read(source, dfn, **)
            return nil, true unless source.key?(dfn[:name]) # Yeah, parsing!
            return source[ dfn[:name].to_sym ], false
          end

          def write(source, dfn, twin:, **)
            twin.send("#{dfn[:name]}=", source)
            twin
          end

          def run_populator(definition, hash, **args)
            definition[:parse_populator].(definition, hash, **args)
          end
        end
      end # Parse

      module ToHash
        extend Runtime

        class << self
          public :run_scalar # FUCK Ruby

          def read(source, dfn, *) # FIXME: just prototyping, we might not need this function.
            return source.send(dfn[:name]), nil
          end

          def run_populator(definition, hash, *args) # TODO: this sucks, how could we undo that step? we don't need it in {#to_hash}.
            definition[:to_hash_populator].(hash, definition, *args)
          end
        end

        module Changed
          extend Runtime
          # extend ToHash

          class << self
            public :run_scalar # FUCK Ruby

            def recurse_nested(dfn, value, *args)
              puts "@@@@@ grabbing @changed #{value.inspect} in >>>>>>>>> #{dfn[:name]}"
              super(dfn, value.instance_variable_get(:@changed))
            end

            def run_populator(definition, hash, *args) # TODO: this sucks, how could we undo that step? we don't need it in {#to_hash}.
              definition[:to_hash_populator].(hash, definition, *args)
            end

            def read(source, dfn, **options) # fixme: from Parse
              Parse.read(source, dfn, **options)
            end
          end
        end
      end

      # grab dfn twin
      # grab dfn errors from "form.errors"
      # write errors to twin
      #   recurse twin's defs

      module ToErrors
        extend Runtime

        class << self
          public :recurse_nested # FUCK Ruby

          # def recurse_nested(dfn, (value, twin), **args)
          #   res=run_definitions(dfn, [value, twin], **args) # FIXME with activity.
          #   twin.errors = value
          #   res
          # end

          # def run_binding(dfn, (source, parent_twin), **args) # this is an Activity in the end.
          #   #value, stop = read(source, dfn, **args) # TODO: use Railway. # TODO: allow to always run populator.

          #   (value, twin), stop = read([source, parent_twin], dfn, **args)
          #   puts "  ??? #{dfn[:name]} {#{twin}"

          #   return twin if stop
          #   puts "@@@@@, #{value.inspect} ..... #{dfn[:name]} #{twin.class}"

          #   value = run_scalar(dfn, [value, twin], **args)

          #   # twin = write(value, dfn, **args)
          #   [value, twin]
          # end

          def run_scalar(definition, value, *args)
            # e.g. recurse_collection
            value, *args = run_populator(definition, value, *args)

            value = send(definition[:recursion], definition, value, *args) # NestedActivity.()
          end


          # # Read property from {Errors} object.
          def read(*args)
            ToHash.read(*args)
          end

          # def run_scalar(dfn, value, **args)
          #   value = send(dfn[:recursion], dfn, value, **args)
          #   value
          # end

          def run_populator(definition, hash, *args)
            pp definition
            # raise hash.inspect
            definition[:to_errors_populator].(hash, definition, *args)
          end

          # value looks like {0=>{:percent=>["must be an integer"]}}
          # def run_collection(definition, value, **args)
          #   puts "::: #{value} "
          #   value.each_w.collect do |i, item|
          #   # raise item.inspect
          #     run_scalar(definition, [item], args.merge(index: i)) # TODO: optimize {i}. TEST!!!!!!!!!
          #   end
          # end

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
