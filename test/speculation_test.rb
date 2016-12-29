require 'test_helper'
require 'speculation/core'
require 'hamster'

class SpeculationTest < Minitest::Test
  S = Speculation::Core
  STest = Speculation::Test
  H = Hamster::Hash
  V = Hamster::Vector
  HSet = Hamster::Set

  using Speculation.namespaced_symbols(Speculation)

  def setup
    Speculation::Core.reset_registry!
  end

  def test_that_it_has_a_version_number
    refute_nil ::Speculation::VERSION
  end

  def test_conform_with_existing_spec
    S.def(:int?.ns, -> (x) { x.is_a?(Integer) })

    assert_equal 2, S.conform(:int?.ns, 2)
    assert_equal :"Speculation/invalid", S.conform(:int?.ns, "two")

    assert S.valid?(:int?.ns, 2)
    refute S.valid?(:int?.ns, "two")
  end

  def test_def_requires_namespaced_symbol
    assert_raises(ArgumentError) { S.def("foo/integer", Integer) }
    assert_raises(ArgumentError) { S.def(:integer, Integer) }
  end

  def test_conform_with_predicate
    predicate = -> (x) { x.is_a?(Integer) }
    assert_equal 2, S.conform(predicate, 2)
    assert_equal :"Speculation/invalid", S.conform(predicate, "two")

    assert S.valid?(predicate, 2)
    refute S.valid?(predicate, "two")
  end

  def test_and_composition
    S.def(:even?.ns, -> (x) { x.even? })

    S.def(:big_even.ns, S.and(Integer, :even?.ns, -> (x) { x > 1000 }))

    assert_equal :"Speculation/invalid", S.conform(:big_even.ns, :foo)
    assert_equal :"Speculation/invalid", S.conform(:big_even.ns, 100)
    assert_equal 1_000_000, S.conform(:big_even.ns, 1_000_000)

    refute S.valid?(:big_even.ns, :foo)
    refute S.valid?(:big_even.ns, 10)
    assert S.valid?(:big_even.ns, 1_000_000)
  end

  def test_or_composition
    S.def(:name_or_id.ns, S.or(name: String, id: Integer))

    assert_equal :"Speculation/invalid", S.conform(:name_or_id.ns, :foo)
    assert_equal [:name, "abc"], S.conform(:name_or_id.ns, "abc")
    assert_equal [:id, 100], S.conform(:name_or_id.ns, 100)
  end

  def test_cat_sequence
    S.def(:boolean.ns, -> (x) { [true, false].include?(x) })
    S.def(:ingredient.ns, S.cat(quantity: Numeric, unit: Symbol))

    expected = H[quantity: 2, unit: :teaspoon]
    assert_equal expected, S.conform(:ingredient.ns, [2, :teaspoon])

    S.def(:config.ns, S.cat(prop: String, val: S.alt(s: String, b: :boolean.ns)))

    assert_equal H[prop: "-server", val: V[:s, "foo"]], S.conform(:config.ns, V["-server", "foo"])
  end

  def test_nested_cat_sequence
    S.def(:nested.ns, S.cat(names_sym: -> (x) { x == :names },
                         names: S.spec(S.cat(name1: String, name2: String)),
                         nums_sym: -> (x) { x == :nums },
                         nums: S.spec(S.cat(num1: Numeric, num2: Numeric))))

    expected = H[names_sym: :names,
                 nums_sym: :nums,
                 nums: H[num1: 1, num2: 2],
                 names: H[name1: "a", name2: "b"]]

    assert_equal expected, S.conform(:nested.ns, [:names, ["a", "b"], :nums, [1, 2]])
  end

  def test_zero_or_more
    S.def(:seq_of_symbols.ns, S.zero_or_more(Symbol))

    assert_equal [:a, :b, :c], S.conform(:seq_of_symbols.ns, [:a, :b, :c])
    assert_equal [], S.conform(:seq_of_symbols.ns, [])
    assert_equal :"Speculation/invalid", S.conform(:seq_of_symbols.ns, [1, 2, 3])
  end

  def test_nested_seq
    S.def(:nested.ns, S.cat(names_sym: -> (x) { x == :names },
                            names: S.spec(S.zero_or_more(String)),
                            nums_sym: -> (x) { x == :nums }, nums: S.spec(S.zero_or_more(Numeric))))

    conformed = S.conform(:nested.ns, [:names, ["a", "b"], :nums, [1, 2]])

    expected = H[names_sym: :names, names: V["a", "b"],
                 nums_sym: :nums, nums: V[1, 2]]

    assert_equal expected, conformed
  end

  def test_non_nested
    S.def(:unnested.ns, S.cat(names_sym: -> (x) { x == :names },
                              names: S.zero_or_more(String),
                              nums_sym: -> (x) { x == :nums },
                              nums: S.zero_or_more(Numeric)))

    expected = H[names_sym: :names, names: V["a", "b"],
                 nums_sym: :nums, nums: V[1, 2, 3]]

    assert_equal expected, S.conform(:unnested.ns, [:names, "a", "b", :nums, 1, 2, 3])
  end

  def test_class_predicate
    S.def(:seq_of_symbols.ns, S.zero_or_more(Symbol))
    assert_equal [:foo, :bar], S.conform(:seq_of_symbols.ns, [:foo, :bar])

    S.def(:seq_of_symbols.ns, S.zero_or_more(Symbol))
    assert_equal [:foo, :bar], S.conform(:seq_of_symbols.ns, [:foo, :bar])
  end

  def test_one_or_more
    S.def(:seq_of_symbols.ns, S.one_or_more(Symbol))

    assert_equal [:a, :b, :c], S.conform(:seq_of_symbols.ns, [:a, :b, :c])
    assert_equal :"Speculation/invalid", S.conform(:seq_of_symbols.ns, [])
  end

  def test_zero_or_one
    S.def(:odd.ns, -> (x) { x.odd? })
    S.def(:even.ns, -> (x) { x.even? })

    S.def(:maybe_odd.ns, S.zero_or_one(:odd.ns))

    assert_equal 1, S.conform(:maybe_odd.ns, [1])
    assert_nil S.conform(:maybe_odd.ns, [])
    assert_equal :"Speculation/invalid", S.conform(:maybe_odd.ns, [2])

    S.def(:odds_then_maybe_even.ns, S.cat(odds: S.one_or_more(:odd.ns),
                                          even: S.zero_or_one(:even.ns)))

    expected = H[odds: V[1, 3, 5], even: 100]
    assert_equal expected, S.conform(:odds_then_maybe_even.ns, [1, 3, 5, 100])
  end

  def test_alt_zero_or_more
    S.def(:config.ns, S.zero_or_more(
      S.cat(prop: String,
            val: S.alt(s: String, b: -> (x) { [true, false].include?(x) }))))

    conformed = S.conform(:config.ns, V["-server", "foo", "-verbose", true, "-user", "joe"])
    expected = V[H[prop: "-server",  val: V[:s, "foo"]],
                 H[prop: "-verbose", val: V[:b, true]],
                 H[prop: "-user",    val: V[:s, "joe"]]]

    assert_equal expected, conformed
  end

  def test_constrained
    S.def(:even_strings.ns,
          S.constrained(S.zero_or_more(String), -> (x) { x.count.even? }))

    refute S.valid?(:even_strings.ns, ["a"])
    assert S.valid?(:even_strings.ns, ["a", "b"])
    refute S.valid?(:even_strings.ns, ["a", "b", "c"])
    assert S.valid?(:even_strings.ns, ["a", "b", "c", "d"])
  end

  def test_hash_keys
    email_regex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,63}$/
    S.def(:email_type.ns, S.and(String, email_regex))

    S.def(:acctid.ns, Integer)
    S.def(:first_name.ns, String)
    S.def(:last_name.ns, String)
    S.def(:email.ns, :email_type.ns)

    S.def(:person.ns,
          S.keys(req: [:first_name.ns, :last_name.ns, :email.ns],
                 opt: [:phone.ns]))

    assert S.valid?(:person.ns, H[:first_name.ns => "Elon",
                                  :last_name.ns  => "Musk",
                                  :email.ns      => "elon@example.com"])

    # Fails required key check
    refute S.valid?(:person.ns, H[:first_name.ns => "Elon"])

    # Invalid value for key not specified in `req`
    refute S.valid?(:person.ns, H[:first_name.ns => "Elon",
                                  :last_name.ns  => "Musk",
                                  :email.ns      => "elon@example.com",
                                  :acctid.ns     => "123"])

    # unqualified keys
    S.def(:person_unq.ns,
          S.keys(req_un: [:first_name.ns, :last_name.ns, :email.ns],
                 opt_un: [:phone.ns]))

    refute S.valid?(:person_unq.ns, H[])

    refute S.valid?(:person_unq.ns, H[first_name: "Elon",
                                      last_name: "Musk",
                                      email: "not-an-email"])

    assert S.valid?(:person_unq.ns, H[first_name: "Elon",
                                      last_name: "Musk",
                                      email: "elon@example.com"])
  end

  def test_coll_of
    S.def(:symbol_collection.ns, S.coll_of(Symbol))

    assert_equal V[:a, :b, :c], S.conform(:symbol_collection.ns, V[:a, :b, :c])
    assert_equal HSet[5, 10, 2], S.conform(S.coll_of(Numeric), HSet[5, 10, 2])

    assert_equal [:a, :b, :c], S.conform(:symbol_collection.ns, [:a, :b, :c])
    assert_equal Set[5, 10, 2], S.conform(S.coll_of(Numeric), Set[5, 10, 2])

    expected = { a: :x, b: :y, c: :z }
    assert_equal expected, S.conform(S.coll_of(:symbol_collection.ns), { a: :x, b: :y, c: :z })

    assert S.valid?(S.coll_of(Integer), [1, 2, 3])
    assert S.valid?(S.coll_of(Integer, kind: -> (coll) { coll.is_a?(Array) }), [1, 2, 3])
    refute S.valid?(S.coll_of(Integer), ['a', 'b', 'c'])
    refute S.valid?(S.coll_of(Integer, kind: -> (coll) { coll.is_a?(V) }), [1, 2, 3])

    assert S.valid?(S.coll_of(Integer, count: 3), [1, 2, 3])
    refute S.valid?(S.coll_of(Integer, count: 2), [1, 2, 3])

    refute S.valid?(S.coll_of(Integer, min_count: 3, max_count: 4), [1, 2])
    assert S.valid?(S.coll_of(Integer, min_count: 3, max_count: 4), [1, 2, 3])
    assert S.valid?(S.coll_of(Integer, min_count: 3, max_count: 4), [1, 2, 3, 4])
    refute S.valid?(S.coll_of(Integer, min_count: 3, max_count: 4), [1, 2, 3, 4, 5])
  end

  def test_tuple
    S.def(:point.ns, S.tuple(Integer, Integer, Integer))

    assert S.valid?(:point.ns, [1, 2, 3])
    refute S.valid?(:point.ns, [1, 2, "3"])
  end

  def test_map_of
    S.def(:scores.ns, S.map_of(String, Integer))

    expected = { "Sally" => 1000, "Joe" => 500 }
    assert_equal expected, S.conform(:scores.ns, { "Sally" => 1000, "Joe" => 500 })

    expected = H["Sally" => 1000, "Joe" => 500]
    assert_equal expected, S.conform(:scores.ns, H["Sally" => 1000, "Joe" => 500])

    refute S.valid?(:scores.ns, H["Sally" => 1000, :Joe => 500])
    refute S.valid?(:scores.ns, { "Sally" => true, "Joe" => 500 })
  end

  def test_explain_data
    S.def(:even.ns, -> (x) { x.even? })

    expected = H[
      :"Speculation/problems" => V[
        H[path: V[], val: 1, via: V[:even.ns], in: V[], pred: "<proc>"]
      ]
    ]
    assert_equal expected, S.explain_data(:even.ns, 1)

    S.def(:integer.ns, Integer)
    S.def(:even.ns, -> (x) { x.even? })
    S.def(:even_integer.ns, S.and(:integer.ns, :even.ns))

    expected = H[
      :"Speculation/problems" => V[
        H[path: V[], val: "s", in: V[], via: V[:even_integer.ns, :integer.ns], pred: Integer]
      ]
    ]
    assert_equal expected, S.explain_data(:even_integer.ns, "s")
  end

  def test_explain_data_map
    email_regex = /^[a-zA-Z1-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,63}$/
    S.def(:email_type.ns, S.and(String, email_regex))

    S.def(:acctid.ns, Integer)
    S.def(:first_name.ns, String)
    S.def(:last_name.ns, String)
    S.def(:email.ns, :email_type.ns)
    S.def(:person.ns,
          S.keys(req: [:first_name.ns, :last_name.ns, :email.ns],
                 opt: [:phone.ns]))

    input = {
      :first_name.ns => "Elon",
      :last_name.ns  => "Musk",
      :email.ns      => "n/a"
    }

    expected = H[
      :"Speculation/problems" => V[
        H[
          path: V[:email.ns],
          val: "n/a",
          in: V[:email.ns],
          via: V[
            :person.ns,
            :email.ns # clojure returns email-type for this...
          ],
          pred: /^[a-zA-Z1-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,63}$/
        ]
      ]
    ]
    assert_equal expected, S.explain_data(:person.ns, input)
  end

  def test_explain_or
    S.def(:name_or_id.ns, S.or(name: String, id: Integer))

    expected = H[
      :"Speculation/problems" => V[
        H[path: V[:name], val: :foo, in: V[], via: V[:name_or_id.ns], pred: String],
        H[path: V[:id], val: :foo, in: V[], via: V[:name_or_id.ns], pred: Integer],
      ]
    ]

    assert_equal expected, S.explain_data(:name_or_id.ns, :foo)
    assert_nil S.explain_data(:name_or_id.ns, 1)
  end

  def test_explain_regex
    S.def(:ingredient.ns, S.cat(quantity: Numeric, unit: Symbol))

    expected = H[:"Speculation/problems" =>
                 V[H[path: V[:unit],
                     val: "peaches",
                     via: V[:ingredient.ns],
                     in: V[1],
                     pred: Symbol]]]

    assert_equal expected, S.explain_data(:ingredient.ns, V[11, "peaches"])

    S.def(:nested.ns, S.cat(names_sym: -> (x) { x == :names },
                            names: S.spec(S.zero_or_more(String)),
                            nums_sym: -> (x) { x == :nums },
                            nums: S.spec(S.constrained(S.one_or_more(Numeric),
                                                       -> (nums) { nums.count.even? }))))

    expected = H[:"Speculation/problems" => V[
      H[:path => V[:nums],
        :val => V[1, 2, 3, 4, 5],
        :in => V[3],
        :via => V[:nested.ns],
        pred: "<proc>"]]] # TODO: need to do better

    assert_equal expected, S.explain_data(:nested.ns, [:names, ["a", "b"], :nums, [1, 2, 3, 4, 5]])
  end

  def test_explain_tuple
    S.def(:point.ns, S.tuple(Float, Float, Float))

    expected = H[:"Speculation/problems" =>
                 V[H[path: V[2],
                     val: 3,
                     via: V[:point.ns],
                     in: V[2],
                     pred: Float]]]


    assert_equal expected, S.explain_data(:point.ns, V[1.1, 2.2, 3])
  end

  def test_explain_map_of
    S.def(:scores.ns, S.map_of(String, Integer))

    expected = H[:"Speculation/problems" =>
                 V[H[path: V[1],
                     val: "300",
                     via: V[:scores.ns],
                     in: V["Joe", 1],
                     pred: Integer]]]

    assert_equal expected, S.explain_data(:scores.ns, H["Sally" => 1000, "Joe" => "300"])
  end

  def test_explain_alt
    S.def(:nested.ns, S.cat(names_sym: -> (x) { x == :names },
                            names: S.spec(S.zero_or_more(String)),
                            nums_sym: -> (x) { x == :nums },
                            nums: S.spec(S.alt(
                              ints: S.one_or_more(Integer),
                              floats: S.one_or_more(Float)))))

    expected = H[:"Speculation/problems" => V[
       H[:path => V[:nums, :ints],
        :val => "1",
        :in => V[3, 0],
        :via => V[:nested.ns],
        :pred => Integer],
       H[:path => V[:nums, :floats],
        :val => "1",
        :in => V[3, 0],
        :via => V[:nested.ns],
        :pred => Float]]]

    assert_equal expected, S.explain_data(:nested.ns, [:names, ["a", "b"], :nums, ["1"]])
  end

  def test_explain
    S.def(:person.ns(:unq),
          S.keys(req_un: [:first_name.ns, :last_name.ns, :email.ns],
                 opt_un: [:phone.ns]))

    assert_equal <<~EOS, S.explain(:person.ns(:unq), first_name: "Elon")
      val: {:first_name=>"Elon"} fails spec: :"unq/person" predicate: "key?(:last_name)"
      val: {:first_name=>"Elon"} fails spec: :"unq/person" predicate: "key?(:email)"
    EOS

    email_regex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,63}$/
    S.def(:email.ns, S.and(String, email_regex))

    assert_equal <<~EOS, S.explain(:person.ns(:unq), first_name: "Elon", last_name: "Musk", email: "elon")
      In: [:email] val: "elon" fails spec: :"Speculation/email" at: [:email] predicate: /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,63}$/
    EOS
  end

  def test_fdef_instrument
    mod = Module.new do
      def self.ranged_rand(start, eend)
        start + rand(eend - start)
      end
    end

    S.fdef(mod.method(:ranged_rand), args: S.and(S.cat(start: Integer, end: Integer),
                                                 -> (args) { args[:start] < args[:end] }))

    STest.instrument(mod.method(:ranged_rand))

    e = assert_raises(STest::DidNotConformError) { mod.ranged_rand(8, 5) }

    assert_match /^Call to 'ranged_rand' did not conform to spec/, e.message

    expected =
      H[:"Speculation/failure" => :instrument,
        :"Speculation/caller" => "/Users/jamie/Projects/speculation/test/speculation_test.rb:449:in `block in test_fdef_instrument'",
        :"Speculation/problems" => V[H[:path => V[:args],
                                       :val => H[:start => 8, :end => 5],
                                       :in => V[],
                                       :via => V[],
                                       :pred => "<proc>"]],
                                       :"Speculation/args" => [8, 5]]

    assert_equal expected, e.explain_data

    mod.ranged_rand(5, 8)
  end

  def test_instrument_instance_method
    klass = Class.new do
      def bar(str)
        "baz"
      end
    end

    S.fdef(klass.instance_method(:bar), args: S.cat(str: String))

    STest.instrument(klass.instance_method(:bar))

    subject = klass.new
    assert_raises(STest::DidNotConformError) { subject.bar(8) }
    subject.bar('asd')
  end
end
