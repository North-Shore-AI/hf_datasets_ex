defmodule HfDatasetsEx.Registry do
  @moduledoc """
  Central registry of all available datasets with metadata.

  Provides discovery, metadata access, and filtering capabilities
  for the dataset collection.

  ## Examples

      iex> HfDatasetsEx.Registry.list_available()
      [:mmlu, :mmlu_stem, :humaneval, :gsm8k]

      iex> HfDatasetsEx.Registry.get_metadata(:mmlu_stem)
      %{
        name: :mmlu_stem,
        domain: "stem",
        description: "MMLU STEM subset covering science, technology, engineering, and mathematics",
        ...
      }

      iex> HfDatasetsEx.Registry.list_by_domain("math")
      [:gsm8k]

      iex> HfDatasetsEx.Registry.list_by_task_type("question_answering")
      [:mmlu, :mmlu_stem, :gsm8k]
  """

  alias HfDatasetsEx.Loader.{
    Chat,
    Code,
    GSM8K,
    HumanEval,
    Math,
    MMLU,
    Preference,
    Reasoning,
    Rubric,
    Vision
  }

  @type dataset_name :: atom()
  @type dataset_metadata :: %{
          name: dataset_name(),
          loader: module(),
          domain: String.t(),
          task_type: String.t(),
          description: String.t(),
          num_items: non_neg_integer() | :unknown,
          license: String.t(),
          source_url: String.t(),
          citation: String.t(),
          languages: [String.t()],
          difficulty: String.t(),
          tags: [String.t()]
        }

  @datasets %{
    mmlu: %{
      name: :mmlu,
      loader: MMLU,
      domain: "general_knowledge",
      task_type: "multiple_choice_qa",
      description:
        "Massive Multitask Language Understanding - 57 subjects across STEM, humanities, and social sciences",
      num_items: 15_908,
      license: "MIT",
      source_url: "https://huggingface.co/datasets/cais/mmlu",
      citation: "Hendrycks et al., 2021",
      languages: ["en"],
      difficulty: "challenging",
      tags: [
        "knowledge",
        "reasoning",
        "multiple_choice",
        "stem",
        "humanities",
        "social_sciences"
      ]
    },
    mmlu_stem: %{
      name: :mmlu_stem,
      loader: MMLU,
      domain: "stem",
      task_type: "multiple_choice_qa",
      description:
        "MMLU STEM subset covering science, technology, engineering, and mathematics subjects",
      num_items: :unknown,
      license: "MIT",
      source_url: "https://huggingface.co/datasets/cais/mmlu",
      citation: "Hendrycks et al., 2021",
      languages: ["en"],
      difficulty: "challenging",
      tags: ["knowledge", "reasoning", "multiple_choice", "stem"]
    },
    humaneval: %{
      name: :humaneval,
      loader: HumanEval,
      domain: "code",
      task_type: "code_generation",
      description:
        "Programming problems with function signatures and test cases for Python code generation",
      num_items: 164,
      license: "MIT",
      source_url: "https://huggingface.co/datasets/openai/openai_humaneval",
      citation: "Chen et al., 2021",
      languages: ["python"],
      difficulty: "medium",
      tags: ["code", "programming", "python", "generation"]
    },
    gsm8k: %{
      name: :gsm8k,
      loader: GSM8K,
      domain: "math",
      task_type: "math_word_problems",
      description:
        "Grade school math word problems requiring multi-step reasoning with natural language solutions",
      num_items: 8500,
      license: "MIT",
      source_url: "https://huggingface.co/datasets/openai/gsm8k",
      citation: "Cobbe et al., 2021",
      languages: ["en"],
      difficulty: "medium",
      tags: ["math", "reasoning", "word_problems", "arithmetic"]
    },
    math_500: %{
      name: :math_500,
      loader: Math,
      domain: "math",
      task_type: "math_reasoning",
      description: "MATH-500 evaluation subset of competition math problems",
      num_items: 500,
      license: "MIT",
      source_url: "https://huggingface.co/datasets/HuggingFaceH4/MATH-500",
      citation: "Hendrycks et al., 2021",
      languages: ["en"],
      difficulty: "challenging",
      tags: ["math", "reasoning"]
    },
    hendrycks_math: %{
      name: :hendrycks_math,
      loader: Math,
      domain: "math",
      task_type: "math_reasoning",
      description: "Competition-level math problems (Hendrycks MATH)",
      num_items: :unknown,
      license: "MIT",
      source_url: "https://huggingface.co/datasets/EleutherAI/hendrycks_math",
      citation: "Hendrycks et al., 2021",
      languages: ["en"],
      difficulty: "challenging",
      tags: ["math", "reasoning"]
    },
    deepmath: %{
      name: :deepmath,
      loader: Math,
      domain: "math",
      task_type: "math_reasoning",
      description: "DeepMath-103K training dataset",
      num_items: :unknown,
      license: "unknown",
      source_url: "https://huggingface.co/datasets/zwhe99/DeepMath-103K",
      citation: "unknown",
      languages: ["en"],
      difficulty: "medium",
      tags: ["math", "reasoning"]
    },
    polaris: %{
      name: :polaris,
      loader: Math,
      domain: "math",
      task_type: "math_reasoning",
      description: "POLARIS 53K math dataset",
      num_items: :unknown,
      license: "unknown",
      source_url: "https://huggingface.co/datasets/POLARIS-Project/Polaris-Dataset-53K",
      citation: "unknown",
      languages: ["en"],
      difficulty: "medium",
      tags: ["math", "reasoning"]
    },
    tulu3_sft: %{
      name: :tulu3_sft,
      loader: Chat,
      domain: "chat",
      task_type: "instruction_following",
      description: "Tulu-3 SFT mixture of instruction-following conversations",
      num_items: :unknown,
      license: "apache-2.0",
      source_url: "https://huggingface.co/datasets/allenai/tulu-3-sft-mixture",
      citation: "unknown",
      languages: ["en"],
      difficulty: "mixed",
      tags: ["chat", "instruction"]
    },
    no_robots: %{
      name: :no_robots,
      loader: Chat,
      domain: "chat",
      task_type: "instruction_following",
      description: "No Robots high-quality instruction-following dataset",
      num_items: :unknown,
      license: "apache-2.0",
      source_url: "https://huggingface.co/datasets/HuggingFaceH4/no_robots",
      citation: "unknown",
      languages: ["en"],
      difficulty: "mixed",
      tags: ["chat", "instruction"]
    },
    hh_rlhf: %{
      name: :hh_rlhf,
      loader: Preference,
      domain: "preference",
      task_type: "preference_modeling",
      description: "Anthropic HH-RLHF preference comparisons",
      num_items: :unknown,
      license: "unknown",
      source_url: "https://huggingface.co/datasets/Anthropic/hh-rlhf",
      citation: "unknown",
      languages: ["en"],
      difficulty: "mixed",
      tags: ["preference", "rlhf"]
    },
    helpsteer3: %{
      name: :helpsteer3,
      loader: Preference,
      domain: "preference",
      task_type: "preference_modeling",
      description: "HelpSteer3 preference dataset",
      num_items: :unknown,
      license: "unknown",
      source_url: "https://huggingface.co/datasets/nvidia/HelpSteer3",
      citation: "unknown",
      languages: ["en"],
      difficulty: "mixed",
      tags: ["preference"]
    },
    helpsteer2: %{
      name: :helpsteer2,
      loader: Preference,
      domain: "preference",
      task_type: "preference_modeling",
      description: "HelpSteer2 preference dataset",
      num_items: :unknown,
      license: "unknown",
      source_url: "https://huggingface.co/datasets/nvidia/HelpSteer2",
      citation: "unknown",
      languages: ["en"],
      difficulty: "mixed",
      tags: ["preference"]
    },
    ultrafeedback: %{
      name: :ultrafeedback,
      loader: Preference,
      domain: "preference",
      task_type: "preference_modeling",
      description: "UltraFeedback binarized preferences",
      num_items: :unknown,
      license: "unknown",
      source_url: "https://huggingface.co/datasets/argilla/ultrafeedback-binarized-preferences",
      citation: "unknown",
      languages: ["en"],
      difficulty: "mixed",
      tags: ["preference"]
    },
    arena_140k: %{
      name: :arena_140k,
      loader: Preference,
      domain: "preference",
      task_type: "preference_modeling",
      description: "Arena human preference 140K comparisons",
      num_items: :unknown,
      license: "unknown",
      source_url: "https://huggingface.co/datasets/lmarena-ai/arena-human-preference-140k",
      citation: "unknown",
      languages: ["en"],
      difficulty: "mixed",
      tags: ["preference"]
    },
    tulu3_preference: %{
      name: :tulu3_preference,
      loader: Preference,
      domain: "preference",
      task_type: "preference_modeling",
      description: "Tulu 3 preference mixture",
      num_items: :unknown,
      license: "unknown",
      source_url:
        "https://huggingface.co/datasets/allenai/llama-3.1-tulu-3-8b-preference-mixture",
      citation: "unknown",
      languages: ["en"],
      difficulty: "mixed",
      tags: ["preference"]
    },
    deepcoder: %{
      name: :deepcoder,
      loader: Code,
      domain: "code",
      task_type: "code_generation",
      description: "DeepCoder code generation dataset",
      num_items: :unknown,
      license: "unknown",
      source_url: "https://huggingface.co/datasets/agentica-org/DeepCoder-Preview-Dataset",
      citation: "unknown",
      languages: ["code"],
      difficulty: "mixed",
      tags: ["code", "generation"]
    },
    open_thoughts3: %{
      name: :open_thoughts3,
      loader: Reasoning,
      domain: "reasoning",
      task_type: "chain_of_thought",
      description: "OpenThoughts3 reasoning traces",
      num_items: :unknown,
      license: "unknown",
      source_url: "https://huggingface.co/datasets/open-thoughts/OpenThoughts3-1.2M",
      citation: "unknown",
      languages: ["en"],
      difficulty: "mixed",
      tags: ["reasoning", "chain_of_thought"]
    },
    deepmath_reasoning: %{
      name: :deepmath_reasoning,
      loader: Reasoning,
      domain: "reasoning",
      task_type: "chain_of_thought",
      description: "DeepMath reasoning variant",
      num_items: :unknown,
      license: "unknown",
      source_url: "https://huggingface.co/datasets/zwhe99/DeepMath-103K",
      citation: "unknown",
      languages: ["en"],
      difficulty: "mixed",
      tags: ["reasoning", "math"]
    },
    feedback_collection: %{
      name: :feedback_collection,
      loader: Rubric,
      domain: "rubric_evaluation",
      task_type: "rubric_grading",
      description: "Feedback-Collection rubric dataset",
      num_items: :unknown,
      license: "apache-2.0",
      source_url: "https://huggingface.co/datasets/prometheus-eval/Feedback-Collection",
      citation: "unknown",
      languages: ["en"],
      difficulty: "mixed",
      tags: ["rubric", "evaluation"]
    },
    caltech101: %{
      name: :caltech101,
      loader: Vision,
      domain: "vision",
      task_type: "image_classification",
      description: "Caltech101 image classification dataset",
      num_items: :unknown,
      license: "unknown",
      source_url: "https://huggingface.co/datasets/dpdl-benchmark/caltech101",
      citation: "unknown",
      languages: [],
      difficulty: "medium",
      tags: ["vision", "image_classification"]
    },
    oxford_flowers102: %{
      name: :oxford_flowers102,
      loader: Vision,
      domain: "vision",
      task_type: "image_classification",
      description: "Oxford Flowers 102 image classification dataset",
      num_items: :unknown,
      license: "unknown",
      source_url: "https://huggingface.co/datasets/dpdl-benchmark/oxford_flowers102",
      citation: "unknown",
      languages: [],
      difficulty: "medium",
      tags: ["vision", "image_classification"]
    },
    oxford_iiit_pet: %{
      name: :oxford_iiit_pet,
      loader: Vision,
      domain: "vision",
      task_type: "image_classification",
      description: "Oxford-IIIT Pet image classification dataset",
      num_items: :unknown,
      license: "unknown",
      source_url: "https://huggingface.co/datasets/dpdl-benchmark/oxford_iiit_pet",
      citation: "unknown",
      languages: [],
      difficulty: "medium",
      tags: ["vision", "image_classification"]
    },
    stanford_cars: %{
      name: :stanford_cars,
      loader: Vision,
      domain: "vision",
      task_type: "image_classification",
      description: "Stanford Cars image classification dataset",
      num_items: :unknown,
      license: "unknown",
      source_url: "https://huggingface.co/datasets/tanganke/stanford_cars",
      citation: "unknown",
      languages: [],
      difficulty: "medium",
      tags: ["vision", "image_classification"]
    }
  }

  @doc """
  List all available dataset names.

  ## Examples

      iex> HfDatasetsEx.Registry.list_available()
      [:mmlu, :mmlu_stem, :humaneval, :gsm8k]
  """
  @spec list_available() :: [dataset_name()]
  def list_available do
    Map.keys(@datasets)
  end

  @doc """
  Get metadata for a specific dataset.

  ## Parameters

    * `name` - Dataset name (atom)

  ## Returns

  Dataset metadata map or `nil` if dataset not found.

  ## Examples

      iex> metadata = HfDatasetsEx.Registry.get_metadata(:mmlu_stem)
      iex> metadata.domain
      "stem"

      iex> HfDatasetsEx.Registry.get_metadata(:unknown)
      nil
  """
  @spec get_metadata(dataset_name()) :: dataset_metadata() | nil
  def get_metadata(name) when is_atom(name) do
    Map.get(@datasets, name)
  end

  @doc """
  List datasets by domain.

  ## Parameters

    * `domain` - Domain string (e.g., "stem", "code", "math")

  ## Examples

      iex> HfDatasetsEx.Registry.list_by_domain("stem")
      [:mmlu_stem]

      iex> HfDatasetsEx.Registry.list_by_domain("code")
      [:humaneval]
  """
  @spec list_by_domain(String.t()) :: [dataset_name()]
  def list_by_domain(domain) when is_binary(domain) do
    @datasets
    |> Enum.filter(fn {_name, metadata} -> metadata.domain == domain end)
    |> Enum.map(fn {name, _metadata} -> name end)
    |> Enum.sort()
  end

  @doc """
  List datasets by task type.

  ## Parameters

    * `task_type` - Task type string (e.g., "multiple_choice_qa", "code_generation")

  ## Examples

      iex> HfDatasetsEx.Registry.list_by_task_type("multiple_choice_qa")
      [:mmlu, :mmlu_stem]

      iex> HfDatasetsEx.Registry.list_by_task_type("code_generation")
      [:humaneval]
  """
  @spec list_by_task_type(String.t()) :: [dataset_name()]
  def list_by_task_type(task_type) when is_binary(task_type) do
    @datasets
    |> Enum.filter(fn {_name, metadata} -> metadata.task_type == task_type end)
    |> Enum.map(fn {name, _metadata} -> name end)
    |> Enum.sort()
  end

  @doc """
  List datasets by difficulty level.

  ## Parameters

    * `difficulty` - Difficulty string ("easy", "medium", "challenging", "hard")

  ## Examples

      iex> HfDatasetsEx.Registry.list_by_difficulty("challenging")
      [:mmlu, :mmlu_stem]
  """
  @spec list_by_difficulty(String.t()) :: [dataset_name()]
  def list_by_difficulty(difficulty) when is_binary(difficulty) do
    @datasets
    |> Enum.filter(fn {_name, metadata} -> metadata.difficulty == difficulty end)
    |> Enum.map(fn {name, _metadata} -> name end)
    |> Enum.sort()
  end

  @doc """
  List datasets by tag.

  ## Parameters

    * `tag` - Tag string (e.g., "reasoning", "knowledge", "code")

  ## Examples

      iex> HfDatasetsEx.Registry.list_by_tag("reasoning")
      [:mmlu, :mmlu_stem, :gsm8k]

      iex> HfDatasetsEx.Registry.list_by_tag("code")
      [:humaneval]
  """
  @spec list_by_tag(String.t()) :: [dataset_name()]
  def list_by_tag(tag) when is_binary(tag) do
    @datasets
    |> Enum.filter(fn {_name, metadata} -> tag in metadata.tags end)
    |> Enum.map(fn {name, _metadata} -> name end)
    |> Enum.sort()
  end

  @doc """
  Search datasets by keyword in description.

  ## Parameters

    * `keyword` - Search term (case-insensitive)

  ## Examples

      iex> HfDatasetsEx.Registry.search("math")
      [:gsm8k, :mmlu_stem]

      iex> HfDatasetsEx.Registry.search("code")
      [:humaneval]
  """
  @spec search(String.t()) :: [dataset_name()]
  def search(keyword) when is_binary(keyword) do
    keyword_lower = String.downcase(keyword)

    @datasets
    |> Enum.filter(fn {_name, metadata} ->
      description_lower = String.downcase(metadata.description)
      String.contains?(description_lower, keyword_lower)
    end)
    |> Enum.map(fn {name, _metadata} -> name end)
    |> Enum.sort()
  end

  @doc """
  Get all metadata as a list.

  Useful for displaying dataset information in tables or UIs.

  ## Examples

      iex> all_metadata = HfDatasetsEx.Registry.all_metadata()
      iex> length(all_metadata)
      4
  """
  @spec all_metadata() :: [dataset_metadata()]
  def all_metadata do
    @datasets
    |> Map.values()
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Check if a dataset is available.

  ## Parameters

    * `name` - Dataset name (atom)

  ## Examples

      iex> HfDatasetsEx.Registry.available?(:mmlu)
      true

      iex> HfDatasetsEx.Registry.available?(:unknown)
      false
  """
  @spec available?(dataset_name()) :: boolean()
  def available?(name) when is_atom(name) do
    Map.has_key?(@datasets, name)
  end

  @doc """
  Get dataset summary statistics.

  Returns aggregate information about the dataset collection.

  ## Examples

      iex> stats = HfDatasetsEx.Registry.stats()
      iex> stats.total_datasets
      4
      iex> stats.domains
      ["code", "general_knowledge", "math", "stem"]
  """
  @spec stats() :: map()
  def stats do
    datasets = Map.values(@datasets)

    %{
      total_datasets: length(datasets),
      domains: datasets |> Enum.map(& &1.domain) |> Enum.uniq() |> Enum.sort(),
      task_types: datasets |> Enum.map(& &1.task_type) |> Enum.uniq() |> Enum.sort(),
      difficulties: datasets |> Enum.map(& &1.difficulty) |> Enum.uniq() |> Enum.sort(),
      all_tags: datasets |> Enum.flat_map(& &1.tags) |> Enum.uniq() |> Enum.sort(),
      by_domain: Enum.frequencies_by(datasets, & &1.domain),
      by_task_type: Enum.frequencies_by(datasets, & &1.task_type),
      by_difficulty: Enum.frequencies_by(datasets, & &1.difficulty)
    }
  end

  @doc """
  Generate a formatted summary of all datasets.

  Returns a human-readable string describing the dataset collection.

  ## Examples

      iex> summary = HfDatasetsEx.Registry.summary()
      iex> String.contains?(summary, "4 datasets")
      true
  """
  @spec summary() :: String.t()
  def summary do
    stats = stats()

    """
    HfDatasetsEx Collection Summary
    ===================================

    Total Datasets: #{stats.total_datasets}

    Domains:
    #{Enum.map_join(stats.domains, "\n", &"  - #{&1}")}

    Task Types:
    #{Enum.map_join(stats.task_types, "\n", &"  - #{&1}")}

    Difficulty Levels:
    #{Enum.map_join(stats.difficulties, "\n", &"  - #{&1}")}

    Available Tags:
    #{stats.all_tags |> Enum.chunk_every(5) |> Enum.map_join("\n", fn chunk -> "  " <> Enum.join(chunk, ", ") end)}

    Datasets by Domain:
    #{Enum.map_join(stats.by_domain, "\n", fn {domain, count} -> "  #{domain}: #{count}" end)}
    """
  end
end
