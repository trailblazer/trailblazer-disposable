require "test_helper"

class TwinTest < Minitest::Spec
  class Collection < Array
  end

  module Expense
    class Twin < Disposable::Twin
      property :id, twin: ->(value) { value }

      collection :taxes, collection_populator: ->(items, definition) { Collection.new(items) } do
        property :amount, twin: ->(value) { value }
        property :percent, twin: ->(value) { value }
      end

      property :total do
        property :amount, twin: ->(value) { value }
        property :currency, twin: ->(value) { value }
      end
    end
  end

  it do
    model = Struct.new(:id, :taxes, :total).new(1, [Struct.new(:amount, :percent).new(99, 19)], Struct.new(:amount, :currency).new(199, "EUR"))

    twin = Disposable::Schema.for_property(
      {nested: Expense::Twin, twin: Expense::Twin, name: "/root"},
      {"/root".to_sym => model},

      populator:   ->(hash, definition:) { definition[:twin].(hash) },

      # definitions: Expense::Twin.definitions,
      # # per "item"
      # # per collection
      # # collection_populator: ->(ary, definition) { snippet },
    )

    puts "result"
    pp twin
    pp twin[1].taxes[0].amount

    twin = twin[1]

    twin.taxes.class.must_equal Collection
  end

  it do
    model = Struct.new(:id, :taxes, :total).new(1, [Struct.new(:amount, :percent).new(99, 19)], Struct.new(:amount, :currency).new(199, "EUR"))

    twin = Disposable::Twin::Schema.from_h(model,
      definitions: Expense::Twin.definitions,
      # per "item"
      populator:   ->(hash, definition:) { definition[:nested].new(hash) },
      # per collection
      # collection_populator: ->(ary, definition) { snippet },
      definition:  {nested: Expense::Twin}
    )

    # read
    twin.id.must_equal 1
    twin.taxes.size.must_equal 1
    twin.taxes[0].amount.must_equal 99
    twin.taxes[0].percent.must_equal 19
    twin.total.amount.must_equal 199
    twin.total.currency.must_equal "EUR"

    # write
    twin.id = 2
    twin.taxes = []
    twin.total.amount = 200

    # updated read
    twin.id.must_equal 2
    twin.taxes.size.must_equal 0
    twin.total.amount.must_equal 200
    twin.total.currency.must_equal "EUR"

    # to_h
    Disposable::Twin.to_h(Expense::Twin, )
  end
end
