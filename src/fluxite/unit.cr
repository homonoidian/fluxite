module Fluxite
  abstract struct BaseMessage
  end

  struct Message(T) < BaseMessage
    def initialize(@sender : Unit, @receiver : IMailbox(T), @object : T)
    end

    def deliver(queue)
      @receiver.receive(queue, @sender, @object)
    end
  end

  module Unit
    def self.join(*units)
      units.reduce { |common, unit| common.or(unit) }
    end

    def self.connect(a : IFanout(T), *, to b : IMailbox(T)) forall T
      a.connect(b)
      b
    end

    def self.disconnect(b : IMailbox(T), *, from a : IFanout(T)) forall T
      a.disconnect(b)
      a
    end

    def self.pass(unit : IFanout(T), object : T) : Nil forall T
      queue = Deque(BaseMessage){Message(T).new(unit, unit, object)}
      while message = queue.shift?
        message.deliver(queue)
      end
    end
  end

  module IFanout(T)
    abstract def send(queue, cls : T.class, object : T) : Nil
    abstract def connect(other : IMailbox(T)) : Nil
    abstract def disconnect(other : IMailbox(T)) : Nil
  end

  module IMailbox(T)
    abstract def receive(queue, sender : Unit, object : T) : Nil
  end

  macro has_fanout(cls)
    include IFanout({{cls}})

    @fanout = [] of IMailbox({{cls}})

    def connect(other : IMailbox({{cls}})) : Nil
      @fanout << other
    end

    def disconnect(other : IMailbox({{cls}})) :  Nil
      @fanout.delete(other)
    end

    def send(queue, cls : ({{cls}}).class, object : {{cls}}) : Nil
      @fanout.each do |receiver|
        queue << Message({{cls}}).new(self, receiver, object)
      end
    end
  end

  class Port(T)
    include Unit
    include IMailbox(T)
    include PipeOut(T)

    Fluxite.has_fanout(T)

    def receive(queue, sender : Unit, object : T) : Nil
      send(queue, T, object)
    end
  end

  # :nodoc:
  class Map(T, U)
    include Unit
    include IMailbox(T)
    include PipeOut(U)

    Fluxite.has_fanout(U)

    def initialize(@fn : T -> U)
    end

    def receive(queue, sender : Unit, object : T) : Nil
      send(queue, U, @fn.call(object))
    end
  end

  # :nodoc:
  class CompactMap(T, U)
    include Unit
    include IMailbox(T)
    include PipeOut(U)

    Fluxite.has_fanout(U)

    def initialize(@fn : T -> U?)
    end

    def receive(queue, sender : Unit, object : T) : Nil
      mapped = @fn.call(object)
      return if mapped.nil?
      send(queue, U, mapped)
    end
  end

  # :nodoc:
  class Select(T)
    include Unit
    include IMailbox(T)
    include PipeOut(T)

    Fluxite.has_fanout(T)

    def initialize(@fn : T -> Bool)
    end

    def receive(queue, sender : Unit, object : T) : Nil
      return unless @fn.call(object)
      send(queue, T, object)
    end
  end

  # :nodoc:
  class SelectAs(T, U)
    include Unit
    include IMailbox(T)
    include PipeOut(U)

    Fluxite.has_fanout(U)

    def receive(queue, sender : Unit, object : T) : Nil
      mapped = object.as?(U)
      return if mapped.nil?
      send(queue, U, mapped)
    end
  end

  # :nodoc:
  class Squash(T)
    include Unit
    include IMailbox(T)
    include PipeOut(T)

    Fluxite.has_fanout(T)

    @memo : {T}?

    def initialize(@eq : T, T -> Bool)
    end

    def initialize(initial : T, eq)
      @memo = {initial}
      initialize(eq)
    end

    def receive(queue, sender : Unit, object : T) : Nil
      if lhs = @memo
        return if @eq.call(*lhs, object)
      end
      @memo = {object}
      send(queue, T, object)
    end
  end

  # :nodoc:
  class SquashBy(T, U)
    include Unit
    include IMailbox(T)
    include PipeOut(T)

    Fluxite.has_fanout(T)

    @memo : {U}?

    def initialize(@fn : T -> U)
    end

    def initialize(initial : U, fn)
      @memo = {initial}
      initialize(fn)
    end

    def receive(queue, sender : Unit, object : T) : Nil
      if lhs = @memo
        rhs = {@fn.call(object)}
        return if lhs == rhs
      else
        rhs = {@fn.call(object)}
      end
      @memo = rhs
      send(queue, T, object)
    end
  end

  # :nodoc:
  class Forward(T, U)
    include Unit
    include IMailbox(T)
    include PipeOut(U)

    Fluxite.has_fanout(U)

    struct Feed(T)
      def initialize(@fanout : IFanout(T), @sender : Unit, @queue : Deque(BaseMessage))
      end

      def call(receiver : IMailbox(T), object : T)
        @queue << Message(T).new(@sender, receiver, object)
      end

      def call(object : T) : Nil
        @fanout.send(@queue, T, object)
      end
    end

    def initialize(@fn : T, Feed(U) ->)
    end

    def receive(queue, sender : Unit, object : T) : Nil
      @fn.call(object, Feed(U).new(self, self, queue))
    end
  end

  enum Cut
    SplitPut
    SplitDrop
    Put
    Drop
  end

  # :nodoc:
  class Batch(T)
    include Unit
    include IMailbox(T)
    include PipeOut(Array(T))

    Fluxite.has_fanout(Array(T))

    def initialize(@fn : Array(T), T -> Cut)
      @batch = [] of T
    end

    def receive(queue, sender : Unit, object : T) : Nil
      case @fn.call(@batch, object)
      in .split_put?
        send(queue, Array(T), @batch)
        @batch = [object]
      in .split_drop?
        send(queue, Array(T), @batch)
        @batch = [] of T
      in .put?
        @batch << object
      in .drop?
      end
    end
  end

  # :nodoc:
  class UpTo(T)
    include Unit
    include IMailbox(T)
    include PipeOut(Array(T))

    Fluxite.has_fanout(Array(T))

    def initialize(@fn : Array(T), T -> Cut)
      @data = [] of T
    end

    def receive(queue, sender : Unit, object : T) : Nil
      case @fn.call(@data, object)
      in .split_put?
        @data = [object]
      in .split_drop?
        @data = [] of T
      in .put?
        @data += [object]
      in .drop?
        return
      end
      send(queue, Array(T), @data)
    end
  end

  # :nodoc:
  class Track(T, U)
    include Unit
    include IMailbox(T | U)
    include PipeOut({T, U})

    Fluxite.has_fanout({T, U})

    @master : {T}?
    @aux : {U}?

    def initialize(@a : Unit, @b : Unit)
    end

    def initialize(default : U, a, b)
      @aux = {default}
      initialize(a, b)
    end

    def receive(queue, sender : Unit, object : T | U) : Nil
      if sender.same?(@a)
        if aux = @aux
          send(queue, {{parse_type("{T, U}")}}, {object.as(T), *aux})
          @master = nil # Aux received, never store master again.
        else            # Wait for aux
          @master = {object.as(T)}
        end
      elsif sender.same?(@b)
        @aux = {object.as(U)}
        return unless master = @master
        send(queue, {{parse_type("{T, U}")}}, {*master, object.as(U)})
        @master = nil
      end
    end
  end

  # :nodoc:
  class During(T)
    include Unit
    include IMailbox(T | Bool)
    include PipeOut(T)

    Fluxite.has_fanout(T)

    def initialize(@source : IFanout(T | Bool), @gate : IFanout(T | Bool))
    end

    def receive(queue, sender : Unit, object : T | Bool) : Nil
      if sender.same?(@gate.as(Unit))
        if object.as(Bool)
          Unit.connect(@source, to: self)
        else
          Unit.disconnect(self, from: @source)
        end
      elsif sender.same?(@source.as(Unit))
        send(queue, T, object.as(T))
      end
    end
  end

  # :nodoc:
  class Before(T, U)
    include Unit
    include IMailbox(T | U)
    include PipeOut(T)

    Fluxite.has_fanout(T)

    def initialize(@source : IFanout(T | U), @gate : IFanout(T | U))
    end

    def receive(queue, sender : Unit, object : T | U) : Nil
      if sender.same?(@source.as(Unit))
        send(queue, T, object.as(T))
      elsif sender.same?(@gate.as(Unit))
        Unit.disconnect(self, from: @source)
        Unit.disconnect(self, from: @gate)
      end
    end
  end

  # :nodoc:
  class After(T, U)
    include Unit
    include IMailbox(T | U)
    include PipeOut(T)

    Fluxite.has_fanout(T)

    def initialize(@source : IFanout(T | U), @gate : IFanout(T | U))
    end

    def receive(queue, sender : Unit, object : T | U) : Nil
      if sender.same?(@source.as(Unit))
        send(queue, T, object.as(T))
      elsif sender.same?(@gate.as(Unit))
        Unit.connect(@source, to: self)
        Unit.disconnect(self, from: @gate)
      end
    end
  end

  # :nodoc:
  class Gate(T)
    include Unit
    include IMailbox(T | Bool)
    include PipeOut({T, Bool})

    Fluxite.has_fanout({T, Bool})

    @memo : {T}?

    def initialize(@source : Unit, @gate : Unit)
      @state = false
      @edge = true
    end

    def receive(queue, sender : Unit, object : T | Bool) : Nil
      if sender.same?(@gate)
        return if @state == object
        @state = object.as(Bool)
        @edge = true
        return unless @state
        return unless memo = @memo
        send(queue, {{parse_type("{T, Bool}")}}, {*memo, true})
        @edge = false
      elsif sender.same?(@source)
        @memo = {object.as(T)}
        return unless @state
        send(queue, {{parse_type("{T, Bool}")}}, {object.as(T), @edge})
        @edge = false
      end
    end
  end

  # :nodoc:
  class Partition(T)
    include Unit
    include IMailbox(T)

    def initialize(@fn : T -> Bool, @yay : IMailbox(T), @nay : IMailbox(T))
    end

    def receive(queue, sender : Unit, object : T) : Nil
      if @fn.call(object)
        @yay.receive(queue, self, object)
      else
        @nay.receive(queue, self, object)
      end
    end
  end

  # :nodoc:
  class Terminal(T)
    include Unit
    include IMailbox(T)

    def initialize(@fn : T ->)
    end

    def receive(queue, sender, object : T) : Nil
      @fn.call(object)
    end
  end
end
