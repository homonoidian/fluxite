require "./fluxite/pipeout"
require "./fluxite/unit"

module Fluxite
  VERSION = "0.1.0"

  def self.pass(*args, **kwargs)
    Unit.pass(*args, **kwargs)
  end

  def self.join(*args, **kwargs)
    Unit.join(*args, **kwargs)
  end

  def self.port(intype : T.class) forall T
    Port(T).new
  end

  def self.port(intype : T.class) forall T
    yield head = Port(T).new
    head
  end
end
