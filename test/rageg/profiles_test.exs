defmodule Rageg.ProfilesTest do
  use ExUnit.Case, async: false

  alias Rageg.{Profile, Profiles}
  alias Rageg.Profiles.FileDiscovery

  describe "Profile.new/2" do
    test "creates a profile with generated ID and defaults" do
      profile = Profile.new("/tmp/test_project")

      assert profile.id != nil
      assert profile.name == "test_project"
      assert profile.path == "/tmp/test_project"
      assert profile.dllb_project_tag == "test_project"
      assert profile.created_at != nil
      assert profile.last_ingested_at == nil
    end

    test "accepts a custom display name" do
      profile = Profile.new("/tmp/test", "My Project")

      assert profile.name == "My Project"
      assert profile.dllb_project_tag == "my_project"
    end
  end

  describe "Profile.from_json/1" do
    test "deserializes from a map" do
      map = %{
        "id" => "abc",
        "name" => "test",
        "path" => "/tmp/test",
        "dllb_project_tag" => "test",
        "created_at" => "2026-01-01T00:00:00Z",
        "last_ingested_at" => nil
      }

      profile = Profile.from_json(map)
      assert profile.id == "abc"
      assert profile.name == "test"
    end
  end

  describe "Profile.mark_ingested/1" do
    test "sets the last_ingested_at timestamp" do
      profile = Profile.new("/tmp/test")
      assert profile.last_ingested_at == nil

      updated = Profile.mark_ingested(profile)
      assert updated.last_ingested_at != nil
    end
  end

  describe "Profiles GenServer" do
    test "active/0 returns nil when no profile is active" do
      assert Profiles.active() == nil
    end

    test "list/0 returns a list" do
      profiles = Profiles.list()
      assert is_list(profiles)
    end

    test "get/1 returns nil for nonexistent ID" do
      assert Profiles.get("nonexistent_id") == nil
    end

    test "create/2 rejects nonexistent directories" do
      assert {:error, _} = Profiles.create("/nonexistent_path_xyz_123")
    end

    test "topic/0 returns the PubSub topic" do
      assert Profiles.topic() == "profiles"
    end
  end

  describe "FileDiscovery.discover/1" do
    test "returns empty list for nonexistent path" do
      assert [] = FileDiscovery.discover("/nonexistent_xyz")
    end

    test "supported_extensions returns a list of strings" do
      exts = FileDiscovery.supported_extensions()
      assert is_list(exts)
      assert ".ex" in exts
      assert ".exs" in exts
    end
  end
end
