require "test_helper"

class DisposableTest < Minitest::Spec
  it do

    # class Ficken < Dry::Struct::Value
    #   attribute :arr, Dry::Types.module::Strict::Array
    # end

    # pp Ficken.new(arr: [ Struct.new(:a).new(1), 2])



    class Expense
      # Define what you _want_ from the source object.
      class Source < Disposable::Twin

        property :id, type: Types::Strict::Int
        property :data do
          collection :taxes do
            property :amount, type: Types::Strict::Int
            property :percent, type: Types::Strict::Int # fixme
          end
          property :country, type: Types::Strict::String
        end
        property :amount, type: Types::Strict::Int
      end
    end

    # pp Expense::Source.definitions["data"][:nested].definitions["taxes"][:nested].instance_variable_get(:@value).new(amount: 1, percent: 2)
    # raise

    source = Struct.new(:id, :data, :amount, :rubbish).new(
      1,
      Struct.new(:taxes, :country).new([
        {
          amount: 1,
          percent: 2,
        }
        ],
        "DEU",
      ),
      99,
      "bla ignore me",
    )

    # we want a immutable twin that matches the Source (but only specified properties, plus defaults, plus coercions?)
    twin = Disposable::Read.from_h(source, definitions: Expense::Source.definitions, populator: ->(hash) { Expense::Source.to_value.new(hash) })

    twin.to_h.must_equal({:id=>1, :data=>{:taxes=>[{:amount=>1, :percent=>2}], :country=>"DEU"}, :amount=>99})

    # to_mutable
  end
end
