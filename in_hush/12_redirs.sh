exec 3>&1
exec 4>&2
echo "stdout via fd 3" >&3
echo "stderr via fd 4" >&4
exec 3>&-
exec 4>&-
