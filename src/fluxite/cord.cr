module Fluxite
  # Cord is a programmatically toggleable connection between two ports. Functionally
  # resembles a valve which you can open (`enable`) or close (`disable`).
  class Cord(T)
    # Returns the input port.
    getter input : Port(T)

    # Returns the output port.
    getter output : Port(T)

    # Returns `true` if this cord is enabled (objects emitted by the input port
    # are passed to the output port). Otherwise, returns `false`.
    getter? enabled

    def initialize(@input : Port(T), @output : Port(T))
      @enabled = false
    end

    # Lets objects pass from the input port to the output port.
    def enable : self
      @enabled = true
      @input.into(@output)

      self
    end

    # Restricts objects from passing from the input port to the output port.
    def disable : self
      @enabled = false
      Unit.disconnect(@output, from: @input)

      self
    end

    def inspect(io)
      io << @input << "/"
      @input.object_id.to_s(io, base: 62)
      if enabled?
        io << " - "
      else
        io << " ⌿ "
      end
      io << @output << "/"
      @output.object_id.to_s(io, base: 62)
    end

    def to_s(io)
      inspect(io)
    end
  end
end
