# cmk_tramp.exs -- rung-3: standalone Elixir CmkTramp (the beam-tramp loop).
#
# A SEPARATE-PROCESS port of the _mk.super.tramp loop. Drives bare `make -f compose.mk
# mk.super.enter/<pid> <ip>` hops as Ports, routes exactly like compose.mk:6601-6630, and
# re-emits each hop's stdout/stderr.
#
# THE UNWIND SEAM, solved with NO core change: each hop sets MAKE_SUPER to its OWN sh pid
# (`$$`). That pid is (a) a real PPid anchor, so the recipe's signal-unwind
# (_mk.super.pid.find, compose.mk:6477) resolves and TRANSFERs/subcommand-handoffs unwind
# correctly; and (b) the cell key -- and it equals the Port's os_pid, so beam-tramp reads
# `.tmp.cmk.mbox.<os_pid>` / `.tmp.mk.super.<os_pid>` for that hop. Scope: DONE / EXIT /
# FAULT / TRANSFER / RESUME (implicit backtrack).
#
# PER-RUN CONTEXT (ctx): the loop threads `%{key, mk}` -- a per-run identity `key` (namespaces
# the CEK cells K/E) and the makefile command `mk` -- through every hop. It NEVER reads a
# VM-global (`:os.getpid()` for the key, `System.get_env("CMK_TRAMP_MK")` for mk), so a SHARED
# resident node can drive many concurrent runs without them clobbering each other's choice
# stack or makefile. The value/mbox cells are already isolated per hop (MAKE_SUPER=$$).
#
# CHOICE PARALLELISM (opt-in, CMK_TRAMP_CHOOSE=parallel): on an unguarded failure with a choice
# frame, run the whole frontier (__vm__.frontier) CONCURRENTLY -- each alt in its own branch ctx
# with a FRESH empty K (so it explores only its subtree and fails on a miss); first exit-0 wins.
# For the UNGUARDED-failure search style; `vm.backtrack`-on-miss programs stay sequential.
#
# Set CMK_TRAMP_TRACE=1 for the hop/route trace.

defmodule CmkTramp do
  @mk_default "make -sS --warn-undefined-variables --no-print-directory -f compose.mk"

  # a per-run context: `key` namespaces the cross-hop CEK cells (choice stack K, env E); `mk` is
  # this run's makefile command. Both threaded so a shared resident stays concurrency-safe.
  defp kf(ctx), do: ".tmp.beamtramp.K.#{ctx.key}"
  defp ef(ctx), do: ".tmp.beamtramp.E.#{ctx.key}"
  # each hop keeps MAKE_SUPER=$$ (per-hop-pid value/mbox routing) but points K/E at this ctx's
  # cells, so parallel branches / concurrent runs never clobber each other.
  defp prefix(ctx), do: "MAKE_SUPER=$$ CONTROL_STACK_FRAMES=#{kf(ctx)} CMK_VMENV=#{ef(ctx)}"

  # cold entry: one BEAM VM per run, so :os.getpid() is a fine unique key; mk from env or default;
  # program stderr goes to this process's own :standard_error.
  def main(argv) do
    ctx = %{key: "#{:os.getpid()}", mk: System.get_env("CMK_TRAMP_MK") || @mk_default, err: :standard_error}
    System.halt(session(Enum.join(argv, " "), ctx))
  end

  # a full boot->loop->exit session for the ip string `ipin` under `ctx`, returning the exit code
  # (no halt). Public so a resident warm node can invoke it by MFA via erpc.
  def session(ipin, ctx) do
    ip0 = if ipin == "", do: "mk.__main__", else: ipin
    File.rm(kf(ctx)); File.rm(ef(ctx))
    trace("boot ip=[#{ip0}] mk=[#{ctx.mk}] key=[#{ctx.key}]")
    {bc, _o, be, _p} = hop(ctx, "mk.super.boot", "CMK_DISABLE_HOOKS=1 CMK_INTERNAL=1 CMK_SUPERVISOR=0")
    IO.write(ctx.err, scrub_stderr(be))
    code = if bc != 0, do: bc, else: run(rewrite_targets(ip0), ctx)
    {_c, _o, xe, _p2} = hop(ctx, "mk.super.exit/#{code}", "CMK_DISABLE_HOOKS=1 CMK_INTERNAL=1")
    IO.write(ctx.err, scrub_stderr(xe))
    code
  end

  # warm-node entry: run a session on THIS (resident) node with the CALLER's group_leader (so the
  # loop's IO streams back to the client terminal), the caller's makefile `mk`, and a caller-supplied
  # unique run `key`. NO VM-global mutation -> safe for CONCURRENT runs on one shared resident.
  def remote_run(ipin, gl, err_dev, mk, key) do
    Process.group_leader(self(), gl)
    ctx = %{key: key, mk: (if mk in [nil, ""], do: @mk_default, else: mk), err: (err_dev || :standard_error)}
    session(ipin, ctx)
  end

  # the loop: run one hop under `ctx`, route on the cells (control-first), recurse.
  defp run(ip, ctx) do
    {rc, out, err, p} = hop(ctx, "mk.super.enter/$$ #{ip}", prefix(ctx))
    IO.write(out)
    IO.write(ctx.err, scrub_stderr(err))

    cond do
      cont_line(p) != nil ->
        cont = cont_line(p)
        trace("TRANSFER rc=#{rc} -> [#{cont}]")
        File.rm(mbox(p)); File.rm(valf(p))
        run(rewrite_targets(cont), ctx)

      rc != 0 and File.exists?(kf(ctx)) ->
        File.rm(valf(p))
        # implicit RESUME: unguarded failure + a choice frame. Default sequential DFS;
        # CMK_TRAMP_CHOOSE=parallel fans the frontier out concurrently.
        alts = if parallel?(), do: frontier(ctx), else: []
        if length(alts) >= 2 do
          trace("PORTFOLIO rc=#{rc} -> #{length(alts)} branches #{inspect(alts)}")
          portfolio(ctx, alts, rc)
        else
          resume_seq(ctx, rc)
        end

      File.exists?(valf(p)) ->
        trace("EXIT/coded rc=#{rc}")
        value_or(p, rc)

      true ->
        # DONE (rc 0) or a genuine FAULT (nonzero, unrouted). The bash tramp also runs
        # mk.super.fault here for a typed diagnosis; that is presentational and needs the
        # fault-module context, so beam-tramp leaves it as a known cosmetic gap.
        trace("#{if rc == 0, do: "DONE", else: "FAULT"} rc=#{rc}")
        rc
    end
  end

  # sequential DFS: take the next untried alt and continue in the SAME ctx.
  defp resume_seq(ctx, rc) do
    case backtrack_next(ctx) do
      "" -> trace("RESUME exhausted rc=#{rc}"); rc
      alt -> trace("RESUME rc=#{rc} -> alt [#{alt}]"); run(alt, ctx)
    end
  end

  # run every frontier alt CONCURRENTLY, each in its own branch ctx with a FRESH empty K (so it
  # explores only its subtree and fails on a miss). First rc==0 wins; async_stream tears the
  # losers down when the reduce halts. All-fail -> the choice is exhausted: return failure.
  # LIMITATION (logged): an OUTER choice frame is not retried here -- this cut parallelizes a
  # single choice point; nested outer backtracking stays on the sequential path.
  defp portfolio(ctx, alts, rc) do
    result =
      alts
      |> Enum.with_index()
      |> Task.async_stream(fn {alt, i} -> {i, run_branch(ctx, alt, i)} end,
           ordered: false, max_concurrency: length(alts), timeout: :infinity)
      |> Enum.reduce_while(nil, fn
           {:ok, {i, 0}}, _ -> {:halt, {:win, i}}
           {:ok, {_i, _rc}}, acc -> {:cont, acc}
           _, acc -> {:cont, acc}
         end)

    case result do
      {:win, i} -> trace("PORTFOLIO win branch=#{i} [#{Enum.at(alts, i)}]"); 0
      _ -> trace("PORTFOLIO exhausted rc=#{rc} (outer-choice fallback not wired)"); rc
    end
  end

  # one branch: a child ctx with a fresh key (own empty K), same makefile. The alt's OWN
  # sub-choices push onto this fresh K and backtrack independently; a bare miss fails nonzero.
  defp run_branch(ctx, alt, i) do
    bctx = %{ctx | key: "#{ctx.key}.b#{i}"}
    File.rm(kf(bctx)); File.rm(ef(bctx))
    rc = run(alt, bctx)
    File.rm(kf(bctx)); File.rm(ef(bctx))
    rc
  end

  defp parallel?, do: System.get_env("CMK_TRAMP_CHOOSE") == "parallel"

  # the untried alternatives of the nearest choice frame (Icon frontier), space-separated.
  defp frontier(ctx) do
    outf = tmp("fr")
    cmd = "MAKE_SUPER=$$ CONTROL_STACK_FRAMES=#{kf(ctx)} CMK_DISABLE_HOOKS=1 CMK_INTERNAL=1 #{ctx.mk} __vm__.frontier > #{outf} 2>/dev/null"
    _ = wait(spawn_sh(cmd))
    String.split(String.trim(rd(outf)), " ", trim: true)
  end

  # a saved real code (mk.exit.code / mk.yield) overrides the raw wait status.
  defp value_or(p, rc) do
    case File.read(valf(p)) do
      {:ok, b} ->
        case Integer.parse(String.trim(b)) do
          {n, ""} -> File.rm(valf(p)); n
          _ -> rc
        end
      _ ->
        rc
    end
  end

  # one hop as a Port under `ctx`: MAKE_SUPER=$$ (self-pid) for the unwind seam; stdout->file,
  # stderr->file, stdin closed. Returns {rc, stdout, stderr, os_pid}.
  defp hop(ctx, goal_str, env_prefix) do
    outf = tmp("out")
    errf = tmp("err")
    cmd = "#{env_prefix} #{ctx.mk} #{goal_str} > #{outf} 2> #{errf} < /dev/null"
    port = spawn_sh(cmd)
    p = case Port.info(port, :os_pid) do
      {:os_pid, n} -> Integer.to_string(n)
      _ -> "none"
    end
    rc = wait(port)
    {rc, rd(outf), rd(errf), p}
  end

  defp spawn_sh(cmd) do
    Port.open({:spawn_executable, sh()}, [
      :binary, :exit_status, :hide,
      {:args, ["-c", cmd]},
      {:env, [{~c"NO_COLOR", ~c"1"}, {~c"TERM", ~c"dumb"}]}
    ])
  end

  defp wait(port) do
    receive do
      {^port, {:exit_status, s}} -> s
      {^port, {:data, _}} -> wait(port)
    end
  end

  # ask the VM for the next untried alternative (reads this ctx's K); "" == exhausted.
  defp backtrack_next(ctx) do
    outf = tmp("bt")
    cmd = "MAKE_SUPER=$$ CONTROL_STACK_FRAMES=#{kf(ctx)} CMK_DISABLE_HOOKS=1 CMK_INTERNAL=1 #{ctx.mk} __vm__.backtrack.next > #{outf} 2>/dev/null"
    _ = wait(spawn_sh(cmd))
    String.trim(rd(outf))
  end

  defp cont_line(p) do
    case File.read(mbox(p)) do
      {:ok, b} ->
        b
        |> String.split("\n", trim: true)
        |> Enum.find(fn l -> String.starts_with?(l, "CONT=") end)
        |> case do
          nil -> nil
          l -> String.trim(String.replace_prefix(l, "CONT=", ""))
        end
      _ ->
        nil
    end
  end

  defp mbox(p), do: ".tmp.cmk.mbox.#{p}"
  defp valf(p), do: ".tmp.mk.super.#{p}"
  defp sh, do: String.to_charlist(System.find_executable("sh") || "/bin/sh")
  defp tmp(t), do: Path.join(System.tmp_dir!(), "tramp_#{t}_#{:erlang.unique_integer([:positive])}")

  defp rd(f) do
    r = case File.read(f) do
      {:ok, b} -> b
      _ -> ""
    end
    File.rm(f)
    r
  end

  # scrub a hop's stderr to bash-tramp parity (mirrors .awk.super.stderr.{split,filter} in
  # compose.mk): first break content stuck before a `make: *** [` marker onto its own line, then
  # drop the SIGINT-unwind block (mk.interrupt/SIGINT Killed .. make: ..Error) + SIGPIPE noise,
  # collapse Interrupt to one notice, dim other make errors. Beam-tramp bypasses the wrapper's
  # `2> >(awk..)` filter, so without this a transfer/backtrack unwind leaks Killed/Error 2 lines.
  defp scrub_stderr(""), do: ""
  defp scrub_stderr(s) do
    s
    |> String.split("\n")
    |> Enum.flat_map(&split_make_marker/1)
    |> filter_lines(false, false, [])
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp split_make_marker(line) do
    case Regex.run(~r/make(?:\[\d+\])?: \*\*\* \[/, line, return: :index) do
      [{start, _} | _] when start > 0 ->
        [binary_part(line, 0, start), binary_part(line, start, byte_size(line) - start)]
      _ ->
        [line]
    end
  end

  # mirror .awk.rewrite.targets.maybe (compose.mk): wrap BARE targets with `flux.pre/X X
  # flux.post/X` (the per-make-level VM ledger + user hooks); slash-/dot- goals and a few keyword
  # goals pass through. Bash applies this to the initial goal (compose.mk:48) and every TRANSFER
  # (:6632), gated on hooks; beam-tramp does the same so bare-target transfers keep flux parity.
  defp rewrite_targets(goal) do
    cond do
      System.get_env("CMK_DISABLE_HOOKS") == "1" -> goal
      Regex.match?(~r/help|jb|yq|jq|include|loadf|cmk/, goal) -> goal
      Regex.match?(~r/mk\.interpret|mk\.compile|lang\.comp\.pipeline/, goal) -> goal
      true ->
        goal
        |> String.split()
        |> Enum.map(fn w ->
          if String.starts_with?(w, ".") or String.contains?(w, "/"),
            do: w,
            else: "flux.pre/#{w} #{w} flux.post/#{w}"
        end)
        |> Enum.join(" ")
    end
  end

  defp filter_lines([], _d, _intr, acc), do: acc
  defp filter_lines([line | rest], d, intr, acc) do
    cond do
      Regex.match?(~r/(write error|standard output): Broken pipe$/, line) ->
        filter_lines(rest, d, intr, acc)
      d ->
        filter_lines(rest, not Regex.match?(~r/^make:.*Error/, line), intr, acc)
      Regex.match?(~r/^make.*:.*mk\.interrupt\/SIGINT.*Killed/, line) ->
        filter_lines(rest, true, intr, acc)
      Regex.match?(~r/^make(?:\[\d+\])?: \*\*\* .*Interrupt *$/, line) ->
        if intr, do: filter_lines(rest, d, intr, acc),
          else: filter_lines(rest, d, true, ["\e[93m\e[1m⚠\e[0m\e[93m interrupted\e[0m" | acc])
      Regex.match?(~r/^make(?:\[\d+\])?: \*\*\* /, line) ->
        filter_lines(rest, d, intr, ["  \e[2m#{line}\e[0m" | acc])
      true ->
        filter_lines(rest, d, intr, [line | acc])
    end
  end

  defp trace(m), do: (if System.get_env("CMK_TRAMP_TRACE") == "1", do: IO.puts(:stderr, "TRAMP: #{m}"))
end

# run the loop only when executed directly; when required as a library (warm-node resident
# sets CMK_TRAMP_LIB=1) just define the module so it can be invoked by MFA over erpc.
unless System.get_env("CMK_TRAMP_LIB") == "1" do
  CmkTramp.main(System.argv())
end
