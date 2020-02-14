() {
  emulate -L zsh -o no_bgnice -o monitor -o err_return
  zmodload zsh/system zsh/net/socket zsh/datetime zsh/zselect
  zmodload -F zsh/files b:zf_rm

  local -F start=EPOCHREALTIME
  local fifo=${TMPDIR:-/tmp}/test.fifo.$sysparams[pid].$EPOCHREALTIME.$RANDOM
  mkfifo $fifo
  local -i req_fd

  exec {req_fd}> >(
    local -i pgid=$sysparams[pid]
    local -i conn_fd
    exec {conn_fd} >$fifo
    {
      trap '' PIPE
      {
        local -a ready
        local req
        unsetopt err_return
        while zselect -a ready 0; do
          local buf=
          sysread 'buf[$#buf+1]' || return
          while [[ $buf != *$'\x1e' ]]; do
            sysread 'buf[$#buf+1]' || return
          done
          for req in ${(ps:\x1e:)buf}; do
            print -rnu $conn_fd -- "x"$'\x1e'
          done
        done
      } always {
        kill -- -$pgid
      }
    } &!
  )

  local -i pgid=$sysparams[procsubstpid]
  local -i conn_fd
  exec {conn_fd} <$fifo
  zf_rm $fifo
  local -F2 took='1e6 * (EPOCHREALTIME - start)'
  print -r -- "startup: $took us"

  sleep 1

  start=EPOCHREALTIME
  repeat 1000; do
    print -rnu $req_fd -- "x"$'\x1e'
    zselect -a ready $conn_fd
    local buf=
    sysread -t 0 -i $conn_fd 'buf[$#buf+1]' || return '$? == 4'
    while [[ $buf == *[^$'\x05\x1e']$'\x05'# ]]; do
      sysread -i $conn_fd 'buf[$#buf+1]' || return
    done
  done
  local -F2 took='1000 * (EPOCHREALTIME - start)'
  print -r -- "latency: $took us"

  start=EPOCHREALTIME
  repeat 1000; do
    print -rnu $req_fd -- "x"$'\x1e'
  done
  local -i received
  while (( received != 1000 )); do
    zselect -a ready $conn_fd
    local buf=
    sysread -t 0 -i $conn_fd 'buf[$#buf+1]' || return '$? == 4'
    while [[ $buf == *[^$'\x05\x1e']$'\x05'# ]]; do
      sysread -i $conn_fd 'buf[$#buf+1]' || return
    done
    received+=${#${(ps:\x1e:)buf}}
  done
  local -F2 took='1000 * (EPOCHREALTIME - start)'
  print -r -- "throughput: $took us/req"

  start=EPOCHREALTIME
  exec {conn_fd}>&-
  exec {req_fd}>&-
  local -F2 took='1e6 * (EPOCHREALTIME - start)'
  print -r -- "shutdown: $took us"
}