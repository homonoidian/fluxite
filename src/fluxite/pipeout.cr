module Fluxite::PipeOut(T)
  def into(other : IMailbox(T))
    Unit.connect(self, to: other)
  end

  def into(other : IMailbox(U)) forall U
    {% unless U.union? && U.union_types.includes?(T) %}
        {% raise "into: expected mailbox for #{T} or a union that includes #{T}, found something else instead: #{U}" %}
      {% end %}

    only(U).into(other)
  end

  def into(other : IFanout(U), &fn : T -> U) : self forall U
    map(&fn).into(other)

    self
  end

  def into(other : IFanout(U), as cls : U.class) : self forall U
    map(cls).into(other)

    self
  end

  def into(&fn : T -> Enumerable(IMailbox(T))) : Nil
    forward(T) do |datum, feed|
      receivers = fn.call(datum)
      receivers.each do |receiver|
        feed.call(receiver, datum)
      end
    end
  end

  # Attaches a terminal function *fn* which consumes data but does not emit any.
  #
  # ```
  # xs = Fluxite::Port(Int32).new
  # xs.each { |x| p! x }
  #
  # Fluxite.pass(xs, 100)
  # Fluxite.pass(xs, 200)
  # Fluxite.pass(xs, 300)
  #
  # # STDOUT:
  # #   x # => 100
  # #   x # => 200
  # #   x # => 300
  # ```
  def each(&fn : T ->)
    into Terminal(T).new(fn)
  end

  # Emits data transformed using *fn*.
  #
  # ```
  # xs = Port(Int32).new
  # xs.map(&.chr).each { |ch| p! ch }
  #
  # Fluxite.pass(xs, 100)
  # Fluxite.pass(xs, 102)
  # Fluxite.pass(xs, 103)
  #
  # # STDOUT:
  # #   ch # => 'd'
  # #   ch # => 'f'
  # #   ch # => 'g'
  # ```
  def map(&fn : T -> U) forall U
    into Map(T, U).new(fn)
  end

  # If `U.class` responds to `[]` (treated as a smart constructor), calls `U[object]`,
  # otherwise, calls `U.new(object)`, where *object* is each incoming object. Emits
  # the resulting instances of `U`.
  #
  # ```
  # class Var
  #   def initialize(@id : UInt32)
  #   end
  # end
  #
  # xs = Fluxite::Port(UInt32).new
  # xs.each { |x| p! x }
  # xs.map(Var).each { |var| p! var }
  #
  # Fluxite.pass(xs, 100u32)
  # Fluxite.pass(xs, 200u32)
  # Fluxite.pass(xs, 300u32)
  #
  # # STDOUT:
  # #   x   # => 100
  # #   var # => #<Var:0x7f273ed30e70 @id=100>
  # #   x   # => 200
  # #   var # => #<Var:0x7f273ed30e60 @id=200>
  # #   x   # => 300
  # #   var # => #<Var:0x7f273ed30e50 @id=300>
  # ```
  def map(cls : U.class) forall U
    map do |object|
      {% if U.class.has_method?(:[]) %}
        U[object]
      {% else %}
        U.new(object)
      {% end %}
    end
  end

  # Similar to `map(cls : U.class)`, but performs elementwise conversion as
  # described by *layout*.
  #
  # ```
  # record Foo, x : Int32
  # record Bar, x : String
  # record Baz, x : Bool
  #
  # xs = Fluxite::Port({Int32, String, Bool}).new
  # xs.map(Foo, Bar, Baz).each { |ys| p! ys }
  #
  # Fluxite.pass(xs, {100, "hello", true})
  # Fluxite.pass(xs, {200, "world", false})
  #
  # # STDOUT:
  # #   ys # => {Foo(@x=100), Bar(@x="hello"), Baz(@x=true)}
  # #   ys # => {Foo(@x=200), Bar(@x="world"), Baz(@x=false)}
  # ```
  def map(*layout : *U) forall U
    {% begin %}
        map do |tuple|
          { {% for cls, index in U %}
              {% if cls.has_method?(:[]) %}
                {{cls.instance}}[tuple[{{index}}]],
              {% else %}
                {{cls.instance}}.new(tuple[{{index}}]),
              {% end %}
            {% end %} }
        end
      {% end %}
  end

  # Similar to `map`, but skips `.nil?` return values of *fn* (so `false`
  # is still emitted).
  #
  # ```
  # xs = Fluxite::Port(Int32).new
  # xs.compact_map { |x| x.even? ? "#{x} even" : nil }.each { |x| p! x }
  #
  # Fluxite.pass(xs, 1)
  # Fluxite.pass(xs, 2)
  # Fluxite.pass(xs, 3)
  # Fluxite.pass(xs, 4)
  #
  # # STDOUT:
  # #   x # => "2 even"
  # #   x # => "4 even"
  # ```
  def compact_map(&fn : T -> U?) forall U
    into CompactMap(T, U).new(fn)
  end

  # Forwards incoming objects to *fn*, emits each element from the enumerable
  # returned by *fn*.
  #
  # ```
  # xs = Fluxite::Port(String).new
  # xs.blast(&.chars).squash.each { |ch| p! ch }
  #
  # Fluxite.pass(xs, "helloo")
  #
  # # STDOUT:
  # #   ch # => 'h'
  # #   ch # => 'e'
  # #   ch # => 'l'
  # #   ch # => 'o'
  # ```
  def blast(&fn : T -> Enumerable(U)) forall U
    forward(U) do |object, feed|
      data = fn.call(object)
      data.each do |datum|
        feed.call(datum)
      end
    end
  end

  # Emits only those incoming objects for which *fn* returns `true`.
  #
  # ```
  # xs = Fluxite::Port(Int32).new
  # xs.select(&.even?).each { |even| p! even }
  #
  # Fluxite.pass(xs, 1)
  # Fluxite.pass(xs, 2)
  # Fluxite.pass(xs, 3)
  # Fluxite.pass(xs, 4)
  #
  # # STDOUT:
  # #   even # => 2
  # #   even # => 4
  # ```
  #
  # See also: `only`.
  def select(&fn : T -> Bool)
    into Select(T).new(fn)
  end

  # Emits incoming objects of type `U`, casting them to type `U`. This method
  # is particularly useful to narrow down a union type. If type cast is impossible
  # the incoming object is ignored.
  #
  # ```
  # xs = Fluxite::Port(Symbol | String | Int32).new
  # xs.select(Symbol).each { |sym| p! sym }
  # xs.select(String).each { |str| p! str }
  # xs.select(Int32).each { |int| p! int }
  #
  # Fluxite.pass(xs, 100)
  # Fluxite.pass(xs, :hello)
  # Fluxite.pass(xs, "world")
  #
  # # STDOUT:
  # #   int # => 100
  # #   sym # => :hello
  # #   str # => "world"
  # ```
  #
  # See also: `only`.
  def select(as cls : U.class) forall U
    {% if T == U %}
      self
    {% else %}
      into SelectAs(T, U).new
    {% end %}
  end

  # Emits only those incoming objects that compare equal to the given *pattern*.
  # Equality is tested using `===`.
  #
  # See also: `only`.
  def select(pattern)
    self.select { |object| pattern === object }
  end

  # Emits only those incoming objects for which *fn* returns `false`.
  #
  # ```
  # xs = Fluxite::Port(Int32).new
  # xs.reject(&.even?).each { |odd| p! odd }
  #
  # Fluxite.pass(xs, 1)
  # Fluxite.pass(xs, 2)
  # Fluxite.pass(xs, 3)
  # Fluxite.pass(xs, 4)
  #
  # # STDOUT:
  # #   odd # => 1
  # #   odd # => 3
  # ```
  def reject(&fn : T -> Bool)
    self.select { |object| !fn.call(object) }
  end

  # Emits only those incoming objects that compare *not* equal to the given
  # *pattern*. Equality is tested using `===`.
  def reject(pattern)
    self.select { |object| !(pattern === object) }
  end

  # Alias of `select` for when you cannot use `select` (as it is a Crystal keyword).
  def only(*args, **kwargs, &fn : T -> Bool)
    self.select(*args, **kwargs, &fn)
  end

  # :ditto:
  def only(*args, **kwargs)
    self.select(*args, **kwargs)
  end

  # Emits an incoming object if it is different from the preceding object.
  # Optionally, the *initial* predecessor may be provided. In such case, the
  # first incoming object is compared with *initial*. Otherwise, the first
  # object is always emitted.
  #
  # Equality of two objects is determined using *fn*.
  #
  # ```
  # max = nil
  #
  # xs = Fluxite::Port(Int32).new
  # xs.squash { |x, y| x >= y }.each { |n| max = n }
  #
  # (-100..100).to_a.shuffle!.each do |n|
  #   Fluxite.pass(xs, n)
  # end
  #
  # max # => 100
  # ```
  def squash(initial : T, &fn : T, T -> Bool)
    into Squash(T).new(initial, fn)
  end

  # :ditto:
  def squash(&fn : T, T -> Bool)
    into Squash(T).new(fn)
  end

  # Emits an incoming object if its return value of *fn* is different from that
  # produced by the preceding object. Optionally, the *initial* value of *fn*
  # may be provided. In such case, the first incoming object is compared with
  # that value. Otherwise, the first object is always emitted.
  #
  # ```
  # # Do not emit consecutive even numbers.
  # xs = Fluxite::Port(Int32).new
  # xs.squash_by(&.even?).each { |x| p! x }
  #
  # Fluxite.pass(xs, 1)
  # Fluxite.pass(xs, 2)
  # Fluxite.pass(xs, 4)
  # Fluxite.pass(xs, 5)
  # Fluxite.pass(xs, 6)
  # Fluxite.pass(xs, 7)
  #
  # # STDOUT:
  # #   x # => 1
  # #   x # => 2
  # #   x # => 5
  # #   x # => 6
  # #   x # => 7
  # ```
  def squash_by(initial : U, &fn : T -> U) forall U
    into SquashBy(T, U).new(initial, fn)
  end

  # :ditto:
  def squash_by(&fn : T -> U) forall U
    into SquashBy(T, U).new(fn)
  end

  # Emits an incoming object if it is different from the preceding one.
  #
  # The objects are compared using `==`.
  #
  # ```
  # xs = Fluxite::Port(Int32).new
  # xs.squash.each { |x| p! x }
  #
  # Fluxite.pass(xs, 1)
  # Fluxite.pass(xs, 2)
  # Fluxite.pass(xs, 2)
  # Fluxite.pass(xs, 3)
  # Fluxite.pass(xs, 2)
  #
  # # STDOUT:
  # #   x # => 1
  # #   x # => 2
  # #   x # => 3
  # #   x # => 2
  # ```
  def squash(*args, **kwargs)
    squash_by(*args, **kwargs, &.itself)
  end

  # Creates and returns two ports, *yay* and *nay*, redirecting those objects
  # for which *fn* returns `true` to *yay*; and those objects for which *fn*
  # returns `false` to *nay*.
  #
  # ```
  # xs = Fluxite::Port(Int32).new
  # even, odd = xs.partition(&.even?)
  # even.each { |even| p! even }
  # odd.each { |odd| p! odd }
  #
  # Fluxite.pass(xs, 1)
  # Fluxite.pass(xs, 2)
  # Fluxite.pass(xs, 3)
  # Fluxite.pass(xs, 4)
  #
  # # STDOUT:
  # #   odd # => 1
  # #   even # => 2
  # #   odd # => 3
  # #   even # => 4
  # ```
  def partition(&fn : T -> Bool)
    yay = Port(T).new
    nay = Port(T).new

    into Partition(T).new(fn, yay, nay)

    {yay, nay}
  end

  # Combines emission of `self` and *other*.
  #
  # ```
  # xs = Fluxite::Port(Symbol).new
  # ys = Fluxite::Port(Int32).new
  #
  # xs.or(ys).each { |common| p! common }
  #
  # Fluxite.pass(xs, :foo)
  # Fluxite.pass(ys, 200)
  # Fluxite.pass(ys, 300)
  # Fluxite.pass(xs, :bar)
  #
  # # STDOUT:
  # #   common # => :foo
  # #   common # => 200
  # #   common # => 300
  # #   common # => :bar
  # ```
  def or(other : IFanout(U)) forall U
    a, b = only(as: T | U), other.only(as: T | U)

    port = Port(T | U).new
    a.into(port)
    b.into(port)

    port
  end

  def forward(cls : U.class, &fn : T, Forward::Feed(U) ->) forall U
    into Forward(T, U).new(fn)
  end

  def batch(&fn : Array(T), T -> Cut)
    into Batch(T).new(fn)
  end

  def up_to(&fn : Array(T), T -> Cut)
    into UpTo(T).new(fn)
  end

  # Emits batches of *n* incoming objects. Waits until the entire batch is
  # collected, and only then emits it. Then starts fresh from a new empty batch.
  #
  # The emitted batch array is fully yours. You can read/mutate it however
  # you want.
  #
  # ```
  # xs = Fluxite::Port(Int32).new
  # xs.batch(3).each { |triple| p! triple }
  #
  # Fluxite.pass(xs, 1)
  # Fluxite.pass(xs, 2)
  # Fluxite.pass(xs, 3)
  # Fluxite.pass(xs, 4)
  # Fluxite.pass(xs, 5)
  # Fluxite.pass(xs, 6)
  # Fluxite.pass(xs, 7)
  #
  # # STDOUT:
  # # triple # => [1, 2, 3]
  # # triple # => [4, 5, 6]
  # ```
  def batch(n : Int)
    batch { |batch, _| batch.size < n ? Cut::Put : Cut::SplitPut }
  end

  # Emits up to *n* incoming objects.
  def up_to(n : Int)
    up_to { |batch, _| batch.size < n ? Cut::Put : Cut::SplitPut }
  end

  def track(other : IFanout(U), default : U) forall U
    a, b = only(as: T | U), other.only(as: T | U)

    track = Track(T, U).new(default, a, b)
    a.into(track)
    b.into(track)

    track
  end

  def track(other : IFanout(U)) forall U
    a, b = only(as: T | U), other.only(as: T | U)

    track = Track(T, U).new(a, b)
    a.into(track)
    b.into(track)

    track
  end

  def during(gate : IFanout(Bool))
    a, b = only(as: T | Bool), gate.only(as: T | Bool)

    during = During(T).new(a, b)
    b.into(during)

    during
  end

  def before(other : IFanout(U)) forall U
    a, b = only(as: T | U), other.only(as: T | U)

    before = Before(T, U).new(a, b)
    a.into(before)
    b.into(before)

    before
  end

  def after(other : IFanout(U)) forall U
    a, b = only(as: T | U), other.only(as: T | U)

    after = After(T, U).new(a, b)
    b.into(after)

    after
  end

  def gate(*, by other : IFanout(Bool))
    a, b = only(as: T | Bool), other.only(as: T | Bool)

    gate = Gate(T).new(a, b)
    a.into(gate)
    b.into(gate)

    gate
  end
end
