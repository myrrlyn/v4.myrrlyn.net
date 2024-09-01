defmodule Home.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Home.Repo,
      {Ecto.Migrator,
        repos: Application.fetch_env!(:home, :ecto_repos),
        skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:home, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Home.PubSub}
      # Start a worker by calling: Home.Worker.start_link(arg)
      # {Home.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Home.Supervisor)
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") != nil
  end
end
