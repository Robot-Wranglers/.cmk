# beam-node-server.exs -- the resident beam-tramp node (warm-node attach backend).
# Loads CmkTramp as a library (CMK_TRAMP_LIB=1 suppresses its auto-run), starts distribution on
# this container's IP (so the make recipe needs no --name/awk), registers a global name, idles.
# Clients invoke CmkTramp.remote_run/5 by MFA via erpc into this warm VM. Reaped at the run exit.
System.put_env("CMK_TRAMP_LIB", "1")
Code.require_file(Path.expand(Path.join(__DIR__, "beam-tramp.exs")))
ip = System.cmd("hostname", ["-i"]) |> elem(0) |> String.split() |> List.first()
System.cmd("epmd", ["-daemon"])   # Node.start (unlike --name) does not auto-start epmd
{:ok, _} = Node.start(String.to_atom("cmk_tramp@#{ip}"), :longnames)
Node.set_cookie(:cmk_beam)
# tag every cmk log line from this node's hops with `<hostname> <beam node id>` via CMK_LOG_PRE
# (node-constant, so this VM-global env is safe even for concurrent runs; hops inherit it).
host = System.cmd("hostname", []) |> elem(0) |> String.trim()
System.put_env("CMK_LOG_PRE", "#{host} #{node()}")
:global.register_name(:cmk_tramp_server, self())
IO.puts(:stderr, "cmk-beam-node up: #{node()}")
receive do
  :never -> :ok
end
