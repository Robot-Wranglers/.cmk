# beam-node-attach.exs -- warm-node client. Starts distribution on this container's IP, connects to
# the resident node (CMK_BEAM_NODE), and runs the beam-tramp loop THERE via erpc, routing the loop's
# IO back to this terminal (group_leader). Exits with the run's code. The run key is globally unique
# (node + unique_integer), so many concurrent attaches to one resident stay isolated (per-run ctx).
ip = System.cmd("hostname", ["-i"]) |> elem(0) |> String.split() |> List.first()
System.cmd("epmd", ["-daemon"])   # Node.start (unlike --name) does not auto-start epmd
{:ok, _} = Node.start(String.to_atom("attach_#{:erlang.unique_integer([:positive])}@#{ip}"), :longnames)
Node.set_cookie(:cmk_beam)
resident = String.to_atom(System.get_env("CMK_BEAM_NODE") || "cmk_tramp@cmk-beam-node")
case Node.connect(resident) do
  true -> :ok
  other -> IO.puts(:stderr, "beam-node-attach: connect failed #{inspect(other)} (#{resident})"); System.halt(3)
end
gl = Process.group_leader()
err = Process.whereis(:standard_error)   # route the loop's program-stderr back to this terminal
ip_goal = Enum.join(System.argv(), " ")
mk = System.get_env("CMK_TRAMP_MK")
key = "run_#{:erlang.phash2(node())}_#{:erlang.unique_integer([:positive])}"
System.halt(:erpc.call(resident, CmkTramp, :remote_run, [ip_goal, gl, err, mk, key], :infinity))
