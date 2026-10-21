defmodule Rageg.TaskRunnerTest do
  use ExUnit.Case, async: false

  alias Rageg.TaskRunner

  # The runner tracks jobs per owner pid, so each test acts as its own
  # LiveView. `start/4` only needs `Phoenix.Component.assign/3` to work, which
  # requires a socket-shaped struct carrying `assigns` and `__changed__`.
  setup do
    {:ok, socket: %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}}
  end

  describe "start/4" do
    test "delivers the job result to the owner", %{socket: socket} do
      socket = TaskRunner.start(socket, :demo, fn -> {:done, 42} end)

      assert socket.assigns.job_tag == :demo
      assert_receive {:task_result, :demo, {:done, 42}}, 2_000
    end

    test "honours a custom assign key", %{socket: socket} do
      socket = TaskRunner.start(socket, :demo, fn -> :ok end, assign_key: :running_job)

      assert socket.assigns.running_job == :demo
      assert_receive {:task_result, :demo, :ok}, 2_000
    end

    test "reports a raised exception as :task_error", %{socket: socket} do
      _socket = TaskRunner.start(socket, :boom, fn -> raise "kaboom" end)

      assert_receive {:task_error, :boom, {:error, %RuntimeError{message: "kaboom"}}}, 2_000
    end

    test "reports a throw as :task_error", %{socket: socket} do
      _socket = TaskRunner.start(socket, :thrown, fn -> throw(:nope) end)

      assert_receive {:task_error, :thrown, {:throw, :nope}}, 2_000
    end
  end

  describe "cancel/1" do
    test "kills a running job and forgets it", %{socket: socket} do
      _socket =
        TaskRunner.start(socket, :slow, fn ->
          # Long enough that cancellation always wins the race.
          Process.sleep(30_000)
          :never
        end)

      assert [%{tag: :slow, pid: pid}] = TaskRunner.jobs()
      ref = Process.monitor(pid)

      assert :ok = TaskRunner.cancel(:slow)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 2_000
      assert TaskRunner.jobs() == []
      refute_receive {:task_result, :slow, _}, 200
    end

    test "returns :not_found for an unknown tag" do
      assert {:error, :not_found} = TaskRunner.cancel(:does_not_exist)
    end
  end

  describe "jobs/0" do
    test "lists only the calling process's jobs", %{socket: socket} do
      _socket = TaskRunner.start(socket, :mine, fn -> Process.sleep(5_000) end)

      assert Enum.map(TaskRunner.jobs(), & &1.tag) == [:mine]
      assert TaskRunner.all_jobs() |> Enum.any?(&(&1.tag == :mine))

      # A different owner sees nothing of ours.
      assert Task.async(fn -> TaskRunner.jobs() end) |> Task.await() == []
    end
  end
end
