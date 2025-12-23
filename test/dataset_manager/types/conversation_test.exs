defmodule HfDatasetsEx.Types.ConversationTest do
  use ExUnit.Case, async: true

  alias HfDatasetsEx.Types.{Message, Conversation}

  describe "new/2" do
    test "creates conversation with messages" do
      messages = [
        Message.new(:user, "Hi"),
        Message.new(:assistant, "Hello!")
      ]

      conv = Conversation.new(messages)

      assert length(conv.messages) == 2
      assert conv.metadata == %{}
    end

    test "creates conversation with metadata" do
      messages = [Message.new(:user, "Hi")]
      conv = Conversation.new(messages, %{source: "test"})

      assert conv.metadata.source == "test"
    end
  end

  describe "from_hf_data/2 with list" do
    test "parses list of message maps" do
      data = [
        %{"role" => "user", "content" => "Hello"},
        %{"role" => "assistant", "content" => "Hi there!"}
      ]

      {:ok, conv} = Conversation.from_hf_data(data)

      assert length(conv.messages) == 2
      assert hd(conv.messages).role == :user
      assert hd(conv.messages).content == "Hello"
    end

    test "returns error for invalid messages" do
      data = [%{"invalid" => "data"}]

      assert {:error, :invalid_message_format} = Conversation.from_hf_data(data)
    end
  end

  describe "from_hf_data/2 with HH-RLHF format" do
    test "parses Human:/Assistant: format" do
      text = "Human: What is 2+2?\n\nAssistant: The answer is 4."

      {:ok, conv} = Conversation.from_hf_data(text)

      assert length(conv.messages) == 2

      [user_msg, assistant_msg] = conv.messages
      assert user_msg.role == :user
      assert user_msg.content =~ "What is 2+2?"
      assert assistant_msg.role == :assistant
      assert assistant_msg.content =~ "The answer is 4"
    end

    test "parses multi-turn conversation" do
      text = """
      Human: Hi

      Assistant: Hello! How can I help?

      Human: What is ML?

      Assistant: Machine learning is a field of AI...
      """

      {:ok, conv} = Conversation.from_hf_data(text)

      assert length(conv.messages) == 4
    end
  end

  describe "turn_count/1" do
    test "counts conversation turns" do
      messages = [
        Message.new(:user, "Q1"),
        Message.new(:assistant, "A1"),
        Message.new(:user, "Q2"),
        Message.new(:assistant, "A2")
      ]

      conv = Conversation.new(messages)

      assert Conversation.turn_count(conv) == 2
    end
  end

  describe "last_message/1" do
    test "returns last message" do
      messages = [
        Message.new(:user, "Hi"),
        Message.new(:assistant, "Hello!")
      ]

      conv = Conversation.new(messages)

      assert Conversation.last_message(conv).content == "Hello!"
    end

    test "returns nil for empty conversation" do
      conv = Conversation.new([])
      assert Conversation.last_message(conv) == nil
    end
  end

  describe "system_prompt/1" do
    test "returns system prompt if present" do
      messages = [
        Message.new(:system, "You are a helpful assistant"),
        Message.new(:user, "Hi")
      ]

      conv = Conversation.new(messages)

      assert Conversation.system_prompt(conv) == "You are a helpful assistant"
    end

    test "returns nil if no system prompt" do
      messages = [Message.new(:user, "Hi")]
      conv = Conversation.new(messages)

      assert Conversation.system_prompt(conv) == nil
    end
  end
end
