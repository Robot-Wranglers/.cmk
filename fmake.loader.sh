# fmake.loader.sh: a CMK_BOOTLOADER ref that parks a zygote on the run's program and routes the run through it.
case "${CMK_FMAKE:-1}" in 0|off|false|no) return 0 ;; esac
_fmake_="${CMK_FMAKE_BIN:-fmake}"
if ! command -v "${_fmake_}" >/dev/null 2>&1; then
  _cmk_bootloader_log "fmake loader: ${_fmake_} is not on PATH; running cold"
  return 0
fi
export FMAKE_REARM="${FMAKE_REARM:-_mk.run.id CMK_IO_STACK CMK_BRF_PREFIX CMK_SCRATCH}"
export FMAKE_REARM_PID="${FMAKE_REARM_PID:-_cmk.pid}"
_fmake_sock_="${TMPDIR:-/tmp}/cmk-fmake.$$.sock"
"${_fmake_}" --serve "${_fmake_sock_}" ${_mkflags_} -f "${CMK_TWIN_PATH:-${0}}" flux.ok </dev/null >/dev/null 2>&1 &
FMAKE_REAPER="kill $! 2>/dev/null; rm -f ${_fmake_sock_}"
_i=0
while [ "${_i}" -lt 200 ] && [ ! -S "${_fmake_sock_}" ]; do _i=$((_i+1)); sleep 0.05; done
if [ -S "${_fmake_sock_}" ]; then
  export FMAKE_CLIENT="${_fmake_} --client ${_fmake_sock_} -- "
  _make_="${FMAKE_CLIENT}${_make_}"
else
  _cmk_bootloader_log "fmake loader: zygote did not start; running cold"
  eval "${FMAKE_REAPER}"
  FMAKE_REAPER=""
fi
