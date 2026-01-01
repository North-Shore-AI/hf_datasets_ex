defmodule HfDatasetsEx.Types.Conversation do
  @moduledoc """
  Represents a multi-turn conversation between user and assistant.

  Used for chat-based datasets like Tulu-3-SFT and No Robots.

  ## Fields

    * `:messages` - List of messages in the conversation
    * `:metadata` - Optional metadata about the conversation (source, id, etc.)

  """

  alias HfDatasetsEx.Types.Message

  @type t :: %__MODULE__{
          messages: [Message.t()],
          metadata: map()
        }

  @enforce_keys [:messages]
  defstruct messages: [], metadata: %{}

  @doc """
  Create a new conversation from a list of messages.

  ## Examples

      iex> messages = [Message.new(:user, "Hi"), Message.new(:assistant, "Hello!")]
      iex> Conversation.new(messages)
      %Conversation{messages: [...], metadata: %{}}

  """
  @spec new([Message.t()], map()) :: t()
  def new(messages, metadata \\ %{}) when is_list(messages) do
    %__MODULE__{
      messages: messages,
      metadata: metadata
    }
  end

  @doc """
  Parse a conversation from HuggingFace data format.

  Supports various formats:
    - List of `%{"role" => ..., "content" => ...}` maps
    - Single string with "Human: ... Assistant: ..." format

  ## Examples

      iex> data = [%{"role" => "user", "content" => "Hi"}, %{"role" => "assistant", "content" => "Hello!"}]
      iex> Conversation.from_hf_data(data)
      {:ok, %Conversation{messages: [...]}}

  """
  @spec from_hf_data(list() | String.t(), map()) :: {:ok, t()} | {:error, term()}
  def from_hf_data(data, metadata \\ %{})

  def from_hf_data(messages, metadata) when is_list(messages) do
    parsed =
      messages
      |> Enum.map(&Message.from_map/1)
      |> Enum.reduce_while([], fn
        {:ok, msg}, acc -> {:cont, [msg | acc]}
        {:error, reason}, _acc -> {:halt, {:error, reason}}
      end)

    case parsed do
      {:error, reason} -> {:error, reason}
      msgs when is_list(msgs) -> {:ok, new(Enum.reverse(msgs), metadata)}
    end
  end

  def from_hf_data(text, metadata) when is_binary(text) do
    # Parse "Human: ... Assistant: ..." format (HH-RLHF style)
    messages = parse_hh_format(text)

    if messages != [] do
      {:ok, new(messages, metadata)}
    else
      {:error, :empty_conversation}
    end
  end

  def from_hf_data(_, _), do: {:error, :invalid_format}

  @doc """
  Convert conversation to a list of maps.
  """
  @spec to_maps(t()) :: [map()]
  def to_maps(%__MODULE__{messages: messages}) do
    Enum.map(messages, &Message.to_map/1)
  end

  @doc """
  Get the number of turns (message pairs) in the conversation.
  """
  @spec turn_count(t()) :: non_neg_integer()
  def turn_count(%__MODULE__{messages: messages}) do
    messages
    |> Enum.filter(&(&1.role in [:user, :assistant]))
    |> length()
    |> div(2)
  end

  @doc """
  Get the last message in the conversation.
  """
  @spec last_message(t()) :: Message.t() | nil
  def last_message(%__MODULE__{messages: []}), do: nil
  def last_message(%__MODULE__{messages: messages}), do: List.last(messages)

  @doc """
  Get the system prompt from the conversation, if any.
  """
  @spec system_prompt(t()) :: String.t() | nil
  def system_prompt(%__MODULE__{messages: messages}) do
    case Enum.find(messages, &(&1.role == :system)) do
      %Message{content: content} -> content
      nil -> nil
    end
  end

  # Parse HH-RLHF style format: "Human: ... Assistant: ..." or "H: ... A: ..."
  defp parse_hh_format(text) do
    # Split on Human:/Assistant:/H:/A: markers (common HH-RLHF formats)
    # Handles both "\n\nHuman:" and "Human:" at line start
    text
    |> String.split(~r/(?:\n*(?:Human:|Assistant:|H:|A:))/, include_captures: true, trim: true)
    |> Enum.chunk_every(2)
    |> Enum.flat_map(fn
      [marker, content] ->
        marker_clean = String.trim(marker)

        cond do
          marker_clean in ["Human:", "H:"] ->
            [Message.new(:user, String.trim(content))]

          marker_clean in ["Assistant:", "A:"] ->
            [Message.new(:assistant, String.trim(content))]

          true ->
            []
        end

      _ ->
        []
    end)
  end
end
