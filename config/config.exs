# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

# Configure Mix tasks and generators
config :home,
  ecto_repos: [Home.Repo]

config :home, Home, site_root: Path.join([File.cwd!(), "apps", "home", "priv", "pages"])

config :home_web,
  ecto_repos: [Home.Repo],
  generators: [context_app: :home]

# Configures the endpoint
config :home_web, HomeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HomeWeb.ErrorHTML, json: HomeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Home.PubSub,
  live_view: [signing_salt: "5SDHJsZf"]

config :dart_sass,
  version: "1.77.8",
  default: [
    args: ~w(-Inode_modules sass/:../priv/static/css/),
    cd: Path.expand("../apps/home_web/assets", __DIR__)
  ]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  home_web: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/home_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
