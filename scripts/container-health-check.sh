for c in $(docker ps --filter health=unhealthy --format '{{.Names}}'); do
  echo "== $c"
  docker inspect --format '{{range .State.Health.Log}}exit={{.ExitCode}} {{.Output}}{{"\n"}}{{end}}' "$c" | tail -n 3
done
