IFS=":"
str="field1::field3:field4:"
set -- $str
echo "Count: $#"
for f in "$@"; do
    printf "[%s]\n" "$f"
done
unset IFS
