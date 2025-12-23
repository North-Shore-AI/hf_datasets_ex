defmodule HfDatasetsEx.Types.MessageTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Types.Message

  describe "new/2" do
    test "creates message with atom role" do
      msg = Message.new(:user, "Hello")

      assert msg.role == :user
      assert msg.content == "Hello"
    end

    test "creates message with string role" do
      msg = Message.new("assistant", "Hi there")

      assert msg.role == :assistant
      assert msg.content == "Hi there"
    end

    test "normalizes 'human' to :user" do
      msg = Message.new("human", "Test")
      assert msg.role == :user
    end

    test "normalizes 'gpt' to :assistant" do
      msg = Message.new("gpt", "Test")
      assert msg.role == :assistant
    end
  end

  describe "from_map/1" do
    test "parses map with string keys" do
      {:ok, msg} = Message.from_map(%{"role" => "user", "content" => "Hello"})

      assert msg.role == :user
      assert msg.content == "Hello"
    end

    test "parses map with atom keys" do
      {:ok, msg} = Message.from_map(%{role: :assistant, content: "Hi"})

      assert msg.role == :assistant
      assert msg.content == "Hi"
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_message_format} = Message.from_map(%{})
      assert {:error, :invalid_message_format} = Message.from_map(%{"role" => "user"})
    end
  end

  describe "to_map/1" do
    test "converts message to map" do
      msg = Message.new(:user, "Hello")
      map = Message.to_map(msg)

      assert map.role == "user"
      assert map.content == "Hello"
    end
  end
end
