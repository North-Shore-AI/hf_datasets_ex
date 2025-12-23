defmodule HfDatasetsEx.Types.Comparison do
  @moduledoc """
  Represents a preference comparison between two responses.

  Used for preference/DPO datasets like HH-RLHF, HelpSteer, and UltraFeedback.

  ## Fields

    * `:prompt` - The prompt/context that led to the responses
    * `:response_a` - First response (either chosen or one option)
    * `:response_b` - Second response (either rejected or another option)
    * `:metadata` - Optional metadata (source, category, etc.)

  """

  alias HfDatasetsEx.Types.Conversation

  @type response :: String.t() | Conversation.t()
  @type t :: %__MODULE__{
          prompt: String.t() | Conversation.t(),
          response_a: response(),
          response_b: response(),
          metadata: map()
        }

  @enforce_keys [:prompt, :response_a, :response_b]
  defstruct [:prompt, :response_a, :response_b, metadata: %{}]

  @doc """
  Create a new comparison.

  ## Examples

      iex> Comparison.new("What is 2+2?", "The answer is 4.", "I don't know.")
      %Comparison{prompt: "What is 2+2?", response_a: "The answer is 4.", response_b: "I don't know."}

  """
  @spec new(String.t() | Conversation.t(), response(), response(), map()) :: t()
  def new(prompt, response_a, response_b, metadata \\ %{}) do
    %__MODULE__{
      prompt: prompt,
      response_a: response_a,
      response_b: response_b,
      metadata: metadata
    }
  end

  @doc """
  Parse a comparison from HH-RLHF format.

  HH-RLHF uses "chosen" and "rejected" fields containing
  "Human: ... Assistant: ..." formatted text.

  ## Examples

      iex> data = %{
      ...>   "chosen" => "Human: Hi\\n\\nAssistant: Hello!",
      ...>   "rejected" => "Human: Hi\\n\\nAssistant: Go away."
      ...> }
      iex> Comparison.from_hh_rlhf(data)
      {:ok, %Comparison{...}}

  """
  @spec from_hh_rlhf(map()) :: {:ok, t()} | {:error, term()}
  def from_hh_rlhf(%{"chosen" => chosen, "rejected" => rejected}) do
    with {:ok, chosen_conv} <- Conversation.from_hf_data(chosen),
         {:ok, rejected_conv} <- Conversation.from_hf_data(rejected) do
      # Extract prompt from the conversation (user turns)
      prompt = extract_prompt(chosen_conv)

      {:ok, new(prompt, chosen_conv, rejected_conv, %{source: :hh_rlhf})}
    end
  end

  def from_hh_rlhf(_), do: {:error, :invalid_hh_rlhf_format}

  @doc """
  Parse a comparison from HelpSteer format.

  HelpSteer uses "prompt", "response_a", "response_b", and "label" fields.

  ## Examples

      iex> data = %{
      ...>   "prompt" => "What is ML?",
      ...>   "response_a" => "Machine Learning is...",
      ...>   "response_b" => "ML means...",
      ...>   "label" => "A"
      ...> }
      iex> Comparison.from_helpsteer(data)
      {:ok, %Comparison{...}}

  """
  @spec from_helpsteer(map()) :: {:ok, t()} | {:error, term()}
  def from_helpsteer(%{"prompt" => prompt, "response_a" => a, "response_b" => b} = data) do
    label = data["label"] || data["winner"]
    metadata = %{source: :helpsteer, label: label}

    {:ok, new(prompt, a, b, metadata)}
  end

  def from_helpsteer(%{"prompt" => prompt, "response" => response, "score" => score}) do
    # Single response with score (HelpSteer2 format)
    metadata = %{source: :helpsteer2, score: score}
    {:ok, new(prompt, response, "", metadata)}
  end

  def from_helpsteer(_), do: {:error, :invalid_helpsteer_format}

  @doc """
  Parse a comparison from UltraFeedback format.

  UltraFeedback uses "prompt", "responses" (list), and rankings/scores.
  """
  @spec from_ultrafeedback(map()) :: {:ok, t()} | {:error, term()}
  def from_ultrafeedback(%{"prompt" => prompt, "responses" => responses} = data)
      when is_list(responses) and length(responses) >= 2 do
    # Get the best and worst responses based on scores
    sorted = sort_by_score(responses)

    best = hd(sorted)
    worst = List.last(sorted)

    metadata = %{
      source: :ultrafeedback,
      model_a: best["model"],
      model_b: worst["model"],
      score_a: best["score"],
      score_b: worst["score"],
      source_id: data["source"]
    }

    {:ok, new(prompt, best["response"], worst["response"], metadata)}
  end

  def from_ultrafeedback(_), do: {:error, :invalid_ultrafeedback_format}

  # Private helpers

  defp extract_prompt(%Conversation{messages: messages}) do
    # Get all user messages as the prompt
    messages
    |> Enum.filter(&(&1.role == :user))
    |> Enum.map(& &1.content)
    |> Enum.join("\n\n")
  end

  defp sort_by_score(responses) do
    Enum.sort_by(responses, fn r ->
      score = r["score"] || r["overall_score"] || 0
      if is_number(score), do: -score, else: 0
    end)
  end
end
