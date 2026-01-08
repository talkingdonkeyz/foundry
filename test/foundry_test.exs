defmodule FoundryTest do
  use ExUnit.Case
  doctest Foundry

  test "greets the world" do
    assert Foundry.hello() == :world
  end
end
