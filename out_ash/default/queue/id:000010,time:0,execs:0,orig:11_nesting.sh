{
    (
        {
            (
                for a in 1; do
                    while false; do :; done
                    case "$a" in
                        1) if true; then echo "nested"; fi ;;
                        *) : ;;
                    esac
                done
            )
        }
    )
}
