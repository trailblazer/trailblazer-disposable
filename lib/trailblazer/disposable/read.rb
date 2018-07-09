module Trailblazer
  module Disposable
    module Read
      module_function

      def from_h(source, definitions:, populator:, definition:)
        ary = definitions.collect do |dfn|
          # next if dfn[:readable] == false # FIXME: is that really what we want?

          value = read(source, dfn)
          # value = hash[ dfn[:private_name] ]
          # value ||= dfn[:default] # FIXME: what if we want nil? Also, optional? Do we need it>

          value = Disposable::Processor::Property.(dfn, value) { |_value, i|
            for_nested(_value, populator: populator, definition: dfn)
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
