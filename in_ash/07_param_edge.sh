unset X
echo "${X:-}"
echo "${X:=default}"
echo "${#X}"
echo "${X:+alternate}"
echo "${X%}"
echo "${X##}"
