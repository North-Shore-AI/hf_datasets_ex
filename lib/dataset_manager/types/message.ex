defmodule HfDatasetsEx.Types.Message do
  @moduledoc """
  Represents a single message in a conversation.

  Used for chat-based datasets like Tulu-3-SFT and No Robots.

  ## Fields

    * `:role` - The role of the message sender ("system", "user", "assistant")
    * `:content` - The message content (text)

  """

  @type role :: :system | :user | :assistant | String.t()
  @type t :: %__MODULE__{
          role: role(),
          content: String.t()
        }

  @enforce_keys [:role, :content]
  defstruct [:role, :content]

  @doc """
  Create a new message.

  ## Examples

      iex> Message.new(:user, "Hello!")
      %Message{role: :user, content: "Hello!"}

      iex> Message.new("assistant", "Hi there!")
      %Message{role: :assistant, content: "Hi there!"}

  """
  @spec new(role(), String.t()) :: t()
  def new(role, content) when is_binary(content) do
    %__MODULE__{
      role: normalize_role(role),
      content: content
    }
  end

  @doc """
  Parse a message from a map (e.g., from HuggingFace data).

  ## Examples

      iex> Message.from_map(%{"role" => "user", "content" => "Hello"})
      {:ok, %Message{role: :user, content: "Hello"}}

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"role" => role, "content" => content}) when is_binary(content) do
    {:ok, new(role, content)}
  end

  def from_map(%{role: role, content: content}) when is_binary(content) do
    {:ok, new(role, content)}
  end

  def from_map(_), do: {:error, :invalid_message_format}

  @doc """
  Convert a message to a map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{role: role, content: content}) do
    %{role: to_string(role), content: content}
  end

  defp normalize_role("system"), do: :system
  defp normalize_role("user"), do: :user
  defp normalize_role("assistant"), do: :assistant
  defp normalize_role("human"), do: :user
  defp normalize_role("Human"), do: :user
  defp normalize_role("gpt"), do: :assistant
  defp normalize_role("bot"), do: :assistant
  defp normalize_role(:system), do: :system
  defp normalize_role(:user), do: :user
  defp normalize_role(:assistant), do: :assistant
  defp normalize_role(other), do: other
end
