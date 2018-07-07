module Trailblazer
  module Disposable
    module Read
      module_function

      def from_h(hash, definitions:, populator:, **)
        ary = definitions.collect do |dfn|
          # next if dfn[:readable] == false # FIXME: is that really what we want?

          value = hash[ dfn[:name].to_sym ]
          # value = hash[ dfn[:private_name] ]
          # value ||= dfn[:default] # FIXME: what if we want nil? Also, optional? Do we need it>

          value = Disposable::Processor.(dfn, value) { |_value, i|
            from_h(_value, definitions: dfn[:nested].definitions, populator: ->(hash) { dfn[:nested].to_value.new(hash) })
          } if dfn[:nested]

          # DISCUSS
          # wrap collections into Twin::Collection.
          # if dfn[:collection]
          #   value = Twin::Collection.for_models(Twin::Twinner.new(Twin::Build, dfn), []) # TODO: make this simpler.
          # end

          [dfn[:name].to_sym, value]
        end.compact

        pp ary

        # TODO: allow injecting an optional class, e.g. Dry-struct or Struct
        populator.(Hash[ary])
      end
    end
  end
end
