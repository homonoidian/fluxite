require "./fluxite/pipeout"
require "./fluxite/unit"

module Fluxite
  VERSION = "0.1.0"

  # Feeds *object* to unit.
  #
  # The main loop resides here, that is responsible for propagating messages
  # in breadth-first manner.
  #
  # Try to avoid calling this method recursively. Instead, consider using `IPipeout#into`,
  # or `IPipeout#forward` with its `Forward::Feed`.
  #
  # ```
  # xs = Fluxite::Port(Int32).new
  # xs.select(&.even?).each { |x| p! x }
  #
  # Fluxite.pass(xs, 100)
  # Fluxite.pass(xs, 101)
  # Fluxite.pass(xs, 102)
  #
  # # STDOUT:
  # #   x # => 100
  # #   x # => 102
  # ```
  def self.pass(unit, object)
    Unit.pass(unit, object)
  end

  # A shorthand for `pass`.
  def self.[](unit, object)
    pass(unit, object)
  end

  # Combines the emission of one or more *units* into a single unit whose
  # output's type is a union of output types of *units*.
  #
  # ```
  # xs = Fluxite::Port(Int32).new
  # ys = Fluxite::Port(Int32).new
  # zs = Fluxite::Port(Int32).new
  #
  # Fluxite.join(xs, ys, zs)
  #   .select(&.even?)
  #   .each { |n| p! n }
  #
  # Fluxite[xs, 100]
  # Fluxite[xs, 101]
  # Fluxite[ys, 102]
  # Fluxite[ys, 103]
  # Fluxite[zs, 104]
  # Fluxite[zs, 105]
  #
  # # STDOUT:
  # #   n # => 100
  # #   n # => 102
  # #   n # => 104
  # ```
  def self.join(*units)
    Unit.join(*units)
  end

  # Creates a port *P* and yields it to the block. The block may attach
  # units to the port. Returns the port *P*.
  #
  # If the block is absent simply creates and returns the port *P*.
  #
  # ```
  # xs = Fluxite.port(Int32, &.squash.map(&.even?).each { |n| p! n })
  #
  # Fluxite[xs, 100]
  # Fluxite[xs, 100]
  # Fluxite[xs, 101]
  # Fluxite[xs, 102]
  # Fluxite[xs, 104]
  #
  # # STDOUT:
  # #   n # => 100
  # #   n # => 102
  # #   n # => 104
  # ```
  macro port(intype, &block)
    {% unless block.is_a?(Nop) || block.args.size == 1 %}
      {% block.raise "expected a block with 1 argument(s) or no block, found a block with #{block.args.size} argument(s)" %}
    {% end %}
    %head = ::Fluxite::Port({{intype}}).new
    {% if block.is_a?(Block) %}
      begin
        {{block.args[0]}} = %head
        {{block.body}}
      end
    {% end %}
    %head
  end
end
