defmodule RagegWeb.Hooks.ProfileHook do
  @moduledoc """
  LiveView `on_mount` hook that subscribes to profile-switch PubSub
  events and forwards them to the `ProfileSwitcher` LiveComponent
  via `send_update/3`.

  Attach in a `live_session`:

      live_session :default,
        on_mount: [RagegWeb.Hooks.ProfileHook]
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Rageg.Profiles

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Rageg.PubSub, Profiles.topic())
    end

    socket = assign(socket, :active_profile, Profiles.active())
    {:cont, attach_hook(socket, :profile_pubsub, :handle_info, &handle_profile_info/2)}
  end

  defp handle_profile_info({:profile_switched, profile}, socket) do
    # Keep the ProfileSwitcher component in sync.
    Phoenix.LiveView.send_update(
      RagegWeb.ProfileSwitcher,
      id: "profile-switcher",
      _action: :profile_switched,
      profile: profile
    )

    # Notify the current LiveView so it can reload path-dependent data.
    # Uses a distinct atom to avoid conflicts with the raw PubSub message.
    send(self(), {:rageg_profile_changed, profile})

    {:halt, assign(socket, :active_profile, profile)}
  end

  defp handle_profile_info(_msg, socket), do: {:cont, socket}
end
