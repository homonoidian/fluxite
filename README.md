# Fluxite

Fluxite is a reactivity/reactive streams-ish library for Crystal. The main feature is that it
uses a message queue instead of recursion allowing (potentially) unbounded feedback.

```crystal
world = Fluxite::Port(Symbol).new
world.select(:tick).map { :tock }.into(world)
world.select(:tock).map { :tick }.into(world)
world.each { |sym| p! sym }

Fluxite.pass(world, :tick)

# STDOUT:
#   sym # => :tick
#   sym # => :tock
#   sym # => :tick
#   sym # => :tock
#   sym # => :tick
#   sym # => :tock
# ... forever
```

Also message propagation is much more intuitive than in more naive reactive streams implementations,
and is more like circuits (Fluxite is breadth-first vs. depth-first naive reactive systems). That is,
progress is made across the entire level of the tree before descending deeper.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     fluxite:
       github: homonoidian/fluxite
   ```

2. Run `shards install`

## Usage

```crystal
require "fluxite"
```

TODO: Write usage instructions here

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/homonoidian/fluxite/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Alexey Yurchenko](https://github.com/homonoidian) - creator and maintainer
