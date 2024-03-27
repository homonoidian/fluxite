require "./spec_helper"

describe Fluxite do
  test "port constructors" do
    assert Fluxite.port(Int32).is_a?(Fluxite::Port(Int32))
    assert Fluxite.port({Int32, String}).is_a?(Fluxite::Port({Int32, String}))

    ys = [] of Int32
    xs = Fluxite.port(Int32, &.select(&.even?).into(ys))

    Fluxite[xs, 1]
    Fluxite[xs, 2]
    Fluxite[xs, 3]
    Fluxite[xs, 4]

    assert ys == [2, 4]
  end

  test "passall" do
    log = [] of Int32
    xs = Fluxite.port(Int32, &.select(&.even?).into(log))

    Fluxite.passall(xs, Set{1, 2, 3, 4})
    Fluxite.passall(xs, [5, 6, 7, 8])
    Fluxite.passall(xs, 9, 10, 11, 12)
    Fluxite[xs, 13, 14, 15, 16]

    assert log == [2, 4, 6, 8, 10, 12, 14, 16]
  end

  test "passall bf" do
    v1 = false
    v2 = false

    log = [] of {Symbol, Bool}

    cmds = Fluxite.port(Symbol)
    cmds.select(:gov1).map { v1 = true; {:v2, v2} }.into(log)
    cmds.select(:gov2).map { v2 = true; {:v1, v1} }.into(log)

    # Depth first
    Fluxite.pass(cmds, :gov1)
    Fluxite.pass(cmds, :gov2)
    assert log == [{:v2, false}, {:v1, true}]
    assert v1 && v2

    log.clear

    # Breadth first
    Fluxite.passall(cmds, :gov1, :gov2)
    assert log == [{:v2, true}, {:v1, true}]
    assert v1 && v2
  end

  test "#each" do
    o = Port(Int32).new

    log = [] of Int32

    o.each { |n| log << n }

    Fluxite[o, 100]
    Fluxite[o, 200]
    Fluxite[o, 300]

    assert log == [100, 200, 300]
  end

  test "#map" do
    o = Port(Int32).new

    log = [] of {Symbol, Int32 | String}

    o.map(&.succ.to_s).into(log) { |n| {:succ, n} }
    o.map(&.pred).into(log) { |n| {:pred, n} }
    o.into(log) { |n| {:each, n} }

    Fluxite[o, 100]
    Fluxite[o, 200]

    assert log == [{:each, 100}, {:succ, "101"}, {:pred, 99}, {:each, 200}, {:succ, "201"}, {:pred, 199}]
  end

  struct X
    def initialize(@x : Int32)
    end
  end

  struct Y
    def initialize(@x : String)
    end

    def self.[](x)
      new(x.to_s)
    end
  end

  test "#map(cls)" do
    o = Port(Int32).new

    log = [] of X | Y

    o.map(X).each { |x| log << x }
    o.map(Y).each { |y| log << y }

    Fluxite[o, 100]
    Fluxite[o, 200]

    assert log == [X.new(100), Y.new("100"), X.new(200), Y.new("200")]
  end

  test "#map(*layout)" do
    o = Port(Array(Int32)).new

    log = [] of {X, Y}

    o.map(X, Y).each { |x| log << x }

    Fluxite[o, [100, 200, 300]]

    assert log == [{X.new(100), Y.new("200")}]

    assert_raises(IndexError) { Fluxite[o, [100]] }

    assert log == [{X.new(100), Y.new("200")}]
  end

  test "#into" do
    o1 = Port(Int32).new
    o2 = Port(Int32).new

    o1.into(o2)

    log = [] of {Symbol, Int32}

    o1.each { |n| log << {:o1, n} }
    o2.each { |n| log << {:o2, n} }

    Fluxite[o1, 100]
    Fluxite[o2, 200]

    assert log == [{:o1, 100}, {:o2, 100}, {:o2, 200}]
  end

  test "#into(&)" do
    o1 = Port(Int32).new
    o2 = Port(String).new

    o1.into(o2) { |n| "n=#{n}" }

    log = [] of {Symbol, Int32 | String}

    o1.each { |n| log << {:o1, n} }
    o2.each { |n| log << {:o2, n} }

    Fluxite[o1, 100]
    Fluxite[o2, "hello world"]

    assert log == [{:o1, 100}, {:o2, "n=100"}, {:o2, "hello world"}]
  end

  test "#into append" do
    squares = [] of Int32

    xs = Fluxite.port(Int32, &.select(&.even?).into(squares) { |n| n ** 2 })

    Fluxite[xs, 1]
    Fluxite[xs, 2]
    Fluxite[xs, 3]
    Fluxite[xs, 4]

    cubes = [] of Int32

    ys = Fluxite.port(Int32, &.select(&.odd?).map { |n| n ** 3 }.into(cubes))

    Fluxite[ys, 1]
    Fluxite[ys, 2]
    Fluxite[ys, 3]
    Fluxite[ys, 4]
    Fluxite[ys, 5]

    assert cubes == [1, 27, 125]
  end

  test "#blast" do
    o = Port(String).new

    log = [] of Char

    o.blast { |x| x.chars.as(Enumerable(Char)) }.each { |ch| log << ch }

    Fluxite[o, "hello"]
    Fluxite[o, "world"]

    assert log == ['h', 'e', 'l', 'l', 'o', 'w', 'o', 'r', 'l', 'd']
  end

  test "#select(&)/#reject(&)" do
    o = Port(Int32).new

    log = [] of {Symbol, Int32}

    o.select(&.even?).each { |n| log << {:even, n} }
    o.reject(&.even?).each { |n| log << {:odd, n} }

    Fluxite[o, 0]
    Fluxite[o, 1]
    Fluxite[o, 2]
    Fluxite[o, 3]
    Fluxite[o, 4]
    Fluxite[o, 5]

    assert log == [{:even, 0}, {:odd, 1}, {:even, 2}, {:odd, 3}, {:even, 4}, {:odd, 5}]
  end

  test "#select(cls)" do
    o = Port(Int32 | String).new

    log = [] of {Symbol, Int32 | String}

    o.select(String).each { |n| log << {:s, n} }
    o.select(Int32).each { |n| log << {:i32, n} }

    Fluxite[o, 0]
    Fluxite[o, "foo"]
    Fluxite[o, 2]
    Fluxite[o, "bar"]
    Fluxite[o, "baz"]

    assert log == [{:i32, 0}, {:s, "foo"}, {:i32, 2}, {:s, "bar"}, {:s, "baz"}]
  end

  test "#squash(&)" do
    o = Port(Int32).new

    last = nil

    o.squash { |a, b| a < b }.each { |n| last = n }

    (-100..100).to_a.shuffle!.each do |n|
      Fluxite[o, n]
    end

    assert last == -100
  end

  test "#squash_by(&)" do
    o = Port(Int32).new

    log = [] of Int32

    o.squash.each { |n| log << n }

    Fluxite[o, 1]
    Fluxite[o, 2]
    Fluxite[o, 3]
    Fluxite[o, 3]
    Fluxite[o, 4]
    Fluxite[o, 10]
    Fluxite[o, 4]
    Fluxite[o, 1]

    assert log == [1, 2, 3, 4, 10, 4, 1]
  end

  test "#partition" do
    o = Port(Int32).new

    log = [] of {Symbol, Int32}

    even, odd = o.partition(&.even?)
    Fluxite.join(
      even.map { |n| {:even, n} },
      odd.map { |n| {:odd, n} }
    ).each { |x| log << x }

    Fluxite[o, 1]
    Fluxite[o, 2]
    Fluxite[o, 3]
    Fluxite[o, 4]

    assert log == [{:odd, 1}, {:even, 2}, {:odd, 3}, {:even, 4}]
  end

  test "#forward" do
    o = Port(String).new

    log = [] of Char

    o.forward(Char) { |s, send| s.chars.each { |ch| send.call(ch) } }
      .each { |ch| log << ch }

    Fluxite[o, "hello"]

    assert log == ['h', 'e', 'l', 'l', 'o']
  end

  test "#track, default absent, a emits first" do
    a = Port(Int32).new
    b = Port(String).new

    log = [] of {Int32, String}

    a.track(b).each { |(x, y)| log << {x, y} }

    Fluxite[a, 100]
    Fluxite[b, "Hello World"]
    Fluxite[a, 200]
    Fluxite[a, 300]
    Fluxite[b, "Foo bar"]
    Fluxite[b, "Bar baz"]
    Fluxite[a, 123]

    assert log == [{100, "Hello World"}, {200, "Hello World"}, {300, "Hello World"}, {123, "Bar baz"}]
  end

  test "#track, default absent, b emits first" do
    a = Port(Int32).new
    b = Port(String).new

    log = [] of {Int32, String}

    a.track(b).each { |(x, y)| log << {x, y} }

    Fluxite[b, "hello world"]
    Fluxite[b, "foo bar"]
    Fluxite[a, 123]
    Fluxite[a, 456]
    Fluxite[b, "baz"]
    Fluxite[a, 200]
    Fluxite[b, "bam"]

    assert log == [{123, "foo bar"}, {456, "foo bar"}, {200, "baz"}]
  end

  test "#track, default present, a emits first" do
    a = Port(Int32).new
    b = Port(String).new

    log = [] of {Int32, String}

    a.track(b, default: "hello world").each { |(x, y)| log << {x, y} }

    Fluxite[a, 100]
    Fluxite[a, 200]
    Fluxite[b, "foobar"]
    Fluxite[b, "baz"]
    Fluxite[a, 123]

    assert log == [{100, "hello world"}, {200, "hello world"}, {123, "baz"}]
  end

  test "#track, default present, b emits first" do
    a = Port(Int32).new
    b = Port(String).new

    log = [] of {Int32, String}

    a.track(b, default: "hello world").each { |(x, y)| log << {x, y} }

    Fluxite[b, "foobar"]
    Fluxite[a, 123]
    Fluxite[a, 456]
    Fluxite[b, "baz"]
    Fluxite[b, "bam"]
    Fluxite[a, 100]

    assert log == [{123, "foobar"}, {456, "foobar"}, {100, "bam"}]
  end

  test "#track, same types" do
    a = Port(Int32).new
    b = Port(Int32).new

    log = [] of {Int32, Int32}

    a.track(b).each { |(x, y)| log << {x, y} }

    Fluxite[b, 1]
    Fluxite[a, 123]
    Fluxite[a, 456]
    Fluxite[b, 2]
    Fluxite[b, 3]
    Fluxite[a, 100]

    assert log == [{123, 1}, {456, 1}, {100, 3}]
  end

  test "#track layouts, basic" do
    m = Fluxite::Port(String).new
    s1 = Fluxite::Port(Int32).new
    s2 = Fluxite::Port(Bool).new
    s3 = Fluxite::Port(Float64).new

    log = [] of {String, Int32, Bool, Float64}

    m.track(s1, s2, s3).each { |a, b, c, d| log << {a, b, c, d} }

    Fluxite[s1, 123]
    Fluxite[m, "hello world"]
    Fluxite[m, "bye world"]
    Fluxite[s2, false]
    Fluxite[s3, 123.456]
    assert log == [{"bye world", 123, false, 123.456}]

    Fluxite[s2, true]
    Fluxite[s1, 456]
    Fluxite[m, "foobar"]
    assert log == [{"bye world", 123, false, 123.456}, {"foobar", 456, true, 123.456}]

    Fluxite[s3, 10.123]
    Fluxite[m, "baz"]
    assert log == [{"bye world", 123, false, 123.456}, {"foobar", 456, true, 123.456}, {"baz", 456, true, 10.123}]
  end

  test "#track, layout mix" do
    m = Fluxite::Port(String).new
    s1 = Fluxite::Port(Int32).new
    s2 = Fluxite::Port(Bool).new
    s3 = Fluxite::Port(Float64).new
    s4 = Fluxite::Port(String | Int32).new

    log = [] of {String, Int32, Bool, Float64, Int32 | String}

    m
      .track(s1, {from: s2, default: false}, {from: s3}, {from: s4, default: "xyzzy"})
      .each { |a, b, c, d, e| log << {a, b, c, d, e} }

    Fluxite[s3, 123.456]
    Fluxite[s1, 400]
    Fluxite[m, "hello world"]
    assert log == [{"hello world", 400, false, 123.456, "xyzzy"}]

    Fluxite[m, "foobar"]

    assert log == [
      {"hello world", 400, false, 123.456, "xyzzy"},
      {"foobar", 400, false, 123.456, "xyzzy"},
    ]

    Fluxite[s2, true]
    Fluxite[m, "foobaz"]

    assert log == [
      {"hello world", 400, false, 123.456, "xyzzy"},
      {"foobar", 400, false, 123.456, "xyzzy"},
      {"foobaz", 400, true, 123.456, "xyzzy"},
    ]

    Fluxite[s4, "baz"]
    Fluxite[m, "bye world"]

    assert log == [
      {"hello world", 400, false, 123.456, "xyzzy"},
      {"foobar", 400, false, 123.456, "xyzzy"},
      {"foobaz", 400, true, 123.456, "xyzzy"},
      {"bye world", 400, true, 123.456, "baz"},
    ]

    Fluxite[s4, 456]
    Fluxite[s3, 10.234]
    Fluxite[m, "foobar"]

    assert log == [
      {"hello world", 400, false, 123.456, "xyzzy"},
      {"foobar", 400, false, 123.456, "xyzzy"},
      {"foobaz", 400, true, 123.456, "xyzzy"},
      {"bye world", 400, true, 123.456, "baz"},
      {"foobar", 400, true, 10.234, 456},
    ]
  end

  test "#during" do
    a = Port(Int32).new
    b = Port(Bool).new

    log = [] of Int32

    a.during(b).each { |n| log << n }

    Fluxite[a, 100]
    Fluxite[b, false]
    Fluxite[a, 200]
    Fluxite[b, true]
    Fluxite[a, 300]
    Fluxite[a, 400]
    Fluxite[a, 500]
    Fluxite[b, false]
    Fluxite[a, 600]

    assert log == [300, 400, 500]
  end

  test "#before, a emits first" do
    a = Port(Int32).new
    b = Port(String).new

    log = [] of Int32

    a.before(b).each { |n| log << n }

    Fluxite[a, 100]
    Fluxite[a, 200]
    Fluxite[b, "hello world"]
    Fluxite[a, 300]
    Fluxite[b, "bye world"]
    Fluxite[a, 400]

    assert log == [100, 200]
  end

  test "#before, b emits first" do
    a = Port(Int32).new
    b = Port(String).new

    log = [] of Int32

    a.before(b).each { |n| log << n }

    Fluxite[b, "hello world"]
    Fluxite[a, 100]
    Fluxite[a, 200]
    Fluxite[b, "bye world"]
    Fluxite[a, 300]

    assert log.empty?
  end

  test "#after, a emits first" do
    a = Port(Int32).new
    b = Port(String).new

    log = [] of Int32

    a.after(b).each { |n| log << n }

    Fluxite[a, 100]
    Fluxite[b, "hello world"]
    Fluxite[a, 200]
    Fluxite[a, 300]
    Fluxite[b, "bye world"]
    Fluxite[a, 400]

    assert log == [200, 300, 400]
  end

  test "#after, b emits first" do
    a = Port(Int32).new
    b = Port(String).new

    log = [] of Int32

    a.after(b).each { |n| log << n }

    Fluxite[b, "hello world"]
    Fluxite[a, 100]
    Fluxite[a, 200]
    Fluxite[a, 300]
    Fluxite[b, "bye world"]
    Fluxite[a, 400]

    assert log == [100, 200, 300, 400]
  end

  test "#gate, a emits first" do
    a = Port(Int32).new
    b = Port(Bool).new

    log = [] of {Int32, Bool}

    a.gate(by: b).each { |data| log << data }

    Fluxite[a, 100]
    Fluxite[a, 200]
    Fluxite[b, false]
    Fluxite[b, false]
    Fluxite[a, 300]
    Fluxite[b, true]
    Fluxite[b, true]
    Fluxite[a, 400]
    Fluxite[a, 500]
    Fluxite[b, false]
    Fluxite[a, 600]
    Fluxite[a, 700]
    Fluxite[b, true]

    assert log == [{300, true}, {400, false}, {500, false}, {700, true}]
  end

  test "#gate, b emits first" do
    a = Port(Int32).new
    b = Port(Bool).new

    log = [] of {Int32, Bool}

    a.gate(by: b).each { |data| log << data }

    Fluxite[b, false]
    Fluxite[b, true]
    Fluxite[a, 100]
    Fluxite[a, 200]
    Fluxite[b, false]
    Fluxite[b, false]
    Fluxite[a, 300]
    Fluxite[a, 400]
    Fluxite[b, true]

    assert log == [{100, true}, {200, false}, {400, true}]
  end

  test "basic feedback support" do
    o = Port(Int32).new
    o.select { |n| n < 10_000 }.map(&.succ).into(o)
    ok = false
    o.select(9_999).each { ok = true }
    Fluxite[o, 0]
    assert ok
  end

  test "basic order sanity" do
    a = Port(Int32).new

    log = [] of Symbol

    a.each { log << :a }
    a.map(&.itself).each { log << :b }
    a.map(&.itself).each { log << :c }
    a.map(&.itself).map(&.itself).each { log << :d }
    a.map(&.itself).map(&.itself).map(&.itself).each { log << :e }

    Fluxite[a, 0]

    assert log == [:a, :b, :c, :d, :e]
  end

  test "sanity 1" do
    log = [] of Bool | Char

    foo = Port(Int32).new
    foo.compact_map { |x| x.even? ? nil : x > 0 }.each { |x| log << x }
    foo.map(&.to_s)
      .blast(&.chars)
      .select(&.number?)
      .reject('0')
      .map { |x| x == '1' ? :foo : x }
      .select(Char)
      .squash('3')
      .each { |y| log << y }

    Fluxite[foo, -103772335]

    assert log == [false, '7', '2', '3', '5']
  end

  def sf2(b, ch)
    case ch
    when .whitespace?
      Cut::SplitDrop
    else
      b.size < 8 ? Cut::Put : Cut::SplitPut
    end
  end

  test "sanity 2" do
    log = [] of String
    last = ""

    w1 = Port(UInt32).new
    w2 = Port(String).new
    w1.map(&.chr).select(&.printable?).batch(&->sf2(Array(Char), Char)).map(&.join).each { |line| log << line }
    w1.map(&.chr).select(&.printable?).recent(&->sf2(Array(Char), Char)).map(&.join).each { |line| last = line }
    outp = w2.forward(Char) do |string, feed|
      string.each_char do |ch|
        feed.call(ch)
      end
    end.map(&.ord.to_u32).into(w1)

    "lorem ipsum._dolor_sit_ametHello World.john_doe_speaking".each_char do |chr|
      Fluxite[w1, chr.ord.to_u32]
    end

    assert log == ["lorem", "ipsum._d", "olor_sit", "_ametHel", "lo", "World.jo", "hn_doe_s"]
    assert last == "peaking"
  end
end
