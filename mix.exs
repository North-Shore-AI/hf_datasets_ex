defmodule HfDatasetsEx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/North-Shore-AI/hf_datasets_ex"

  def project do
    [
      app: :hf_datasets_ex,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      dialyzer: [plt_add_apps: [:mix]],
      description: description(),
      package: package(),
      name: "HfDatasetsEx",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def cli do
    [preferred_envs: ["test.live": :test]]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.3"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},

      # HuggingFace Hub client (API, downloads, caching, auth)
      {:hf_hub, "~> 0.1.1"},

      # DataFrames + Parquet support
      {:explorer, "~> 0.11.1"},

      # Image decoding (libvips)
      {:vix, "~> 0.35"},

      # Documentation
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},

      # Test utilities
      {:bypass, "~> 2.1", only: :test}
    ]
  end

  defp description do
    """
    HuggingFace Datasets for Elixir - Load, stream, and process ML datasets from the HuggingFace Hub with native BEAM/OTP integration.
    """
  end

  defp docs do
    [
      main: "readme",
      name: "HfDatasetsEx",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      logo: "assets/hf_datasets_ex.svg",
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      assets: %{"assets" => "assets"},
      before_closing_head_tag: &mermaid_config/1
    ]
  end

  defp extras do
    [
      "README.md",
      "CHANGELOG.md",
      "LICENSE"
    ]
  end

  defp groups_for_extras do
    [
      Guides: ["README.md"],
      "Release Notes": ["CHANGELOG.md"]
    ]
  end

  defp mermaid_config(:html) do
    """
    <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
    <script>
      let initialized = false;

      window.addEventListener("exdoc:loaded", () => {
        if (!initialized) {
          mermaid.initialize({
            startOnLoad: false,
            theme: document.body.className.includes("dark") ? "dark" : "default"
          });
          initialized = true;
        }

        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp mermaid_config(_), do: ""

  defp package do
    [
      name: "hf_datasets_ex",
      description: description(),
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Online documentation" => "https://hexdocs.pm/hf_datasets_ex",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["nshkrdotcom"]
    ]
  end
end
